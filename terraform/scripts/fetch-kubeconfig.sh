#!/usr/bin/env bash
# Terraform external data source: reads {host, key_pem} JSON on stdin,
# SSHes the k3s server with the cluster's generated private key, fetches the
# kubeconfig, rewrites the loopback address to the server's public IP, and
# prints {"kubeconfig": "..."} JSON. Surfaces the real SSH error on stderr.
set -euo pipefail

input="$(cat)"
HOST="$(jq -r '.host' <<<"$input")"

KEY="$(mktemp)"
err_file="$(mktemp)"
trap 'rm -f "$KEY" "$err_file"' EXIT

jq -r '.key_pem' <<<"$input" >"$KEY"
chmod 600 "$KEY"

if ! ssh-keygen -y -P "" -f "$KEY" >/dev/null 2>&1; then
  echo "generated cluster key is invalid (tls_private_key.cluster)" >&2
  exit 1
fi

SSH=(ssh -i "$KEY"
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o BatchMode=yes
  -o ConnectTimeout=10
  "ubuntu@$HOST")

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
