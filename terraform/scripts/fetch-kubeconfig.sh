#!/usr/bin/env bash
# Terraform external data source: reads {host, key} JSON on stdin,
# SSHes the k3s server, fetches the kubeconfig, rewrites the loopback
# address to the server's public IP, and prints {"kubeconfig": "..."} JSON.
set -euo pipefail

eval "$(jq -r '@sh "HOST=\(.host) KEY=\(.key)"')"
KEY="${KEY/#\~/$HOME}"

SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=10 "ubuntu@$HOST")

KC=""
for _ in $(seq 1 30); do
  if KC="$("${SSH[@]}" 'sudo cat /etc/rancher/k3s/k3s.yaml' 2>/dev/null)"; then
    [ -n "$KC" ] && break
  fi
  sleep 10
done

[ -n "$KC" ] || {
  echo "kubeconfig not ready on $HOST after retries" >&2
  exit 1
}

KC="${KC//127.0.0.1/$HOST}"
jq -n --arg kc "$KC" '{kubeconfig: $kc}'
