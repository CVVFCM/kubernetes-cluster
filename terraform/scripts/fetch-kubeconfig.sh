#!/usr/bin/env bash
# Terraform external data source: reads {host, key} JSON on stdin,
# SSHes the k3s server, fetches the kubeconfig, rewrites the loopback
# address to the server's public IP, and prints {"kubeconfig": "..."} JSON.
# On failure it surfaces the real SSH error on stderr (Terraform shows it).
set -euo pipefail

eval "$(jq -r '@sh "HOST=\(.host) KEY=\(.key)"')"
KEY="${KEY/#\~/$HOME}"

if [ ! -s "$KEY" ]; then
  echo "ssh key file missing or empty: $KEY (is the SSH_PRIVATE_KEY secret set?)" >&2
  exit 1
fi

SSH=(ssh -i "$KEY"
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o BatchMode=yes
  -o ConnectTimeout=10
  "ubuntu@$HOST")

err_file="$(mktemp)"
trap 'rm -f "$err_file"' EXIT

for _ in $(seq 1 18); do
  if KC="$("${SSH[@]}" 'sudo cat /etc/rancher/k3s/k3s.yaml' 2>"$err_file")" && [ -n "$KC" ]; then
    KC="${KC//127.0.0.1/$HOST}"
    jq -n --arg kc "$KC" '{kubeconfig: $kc}'
    exit 0
  fi
  sleep 10
done

echo "kubeconfig not ready on $HOST after retries. Last SSH error: $(tr '\n' ' ' <"$err_file")" >&2
exit 1
