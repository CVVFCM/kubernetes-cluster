# AGENTS.md

Infrastructure-as-code that provisions the CVVFCM sailing club's Kubernetes
cluster on **Oracle Cloud Always-Free tier**. Everything is OpenTofu under
`terraform/`. There is no application code here — this repo builds the cluster
and its in-cluster platform (ingress, storage, TLS, DNS), then hands a
kubeconfig to other repos via a GitHub org secret.

## Tooling

Use **OpenTofu (`tofu`)**, not `terraform` — CI runs `opentofu/setup-opentofu`.
The `oci` CLI must be on PATH for any `apply`/`plan` that touches in-cluster
resources (the kubernetes/helm/kubectl providers exec `oci ce cluster
generate-token` to reach the API).

```bash
cd terraform
tofu init -input=false
tofu fmt -check        # CI fails on unformatted HCL; run `tofu fmt` to fix
tofu validate
tflint --init && tflint
tofu plan -input=false
```

Local applies need credentials in env: `GITHUB_TOKEN` (PAT, admin:org),
`CLOUDFLARE_API_TOKEN`, `TF_VAR_cloudflare_dns_api_token`, and the Scaleway S3
keys as `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` (state backend). OCI auth
comes from `terraform.tfvars` (gitignored; copy from `terraform.tfvars.example`).

## Two-phase first apply (critical)

On a clean state the kubernetes/helm/kubectl providers cannot configure —
their host/CA (`locals.tf`) are derived from a cluster that doesn't exist yet.
Bootstrap in two steps:

```bash
tofu apply -target=oci_containerengine_cluster.main -target=oci_containerengine_node_pool.workers
tofu apply        # add-ons, DNS, org secrets
```

Subsequent applies are single-phase. `addons.tf` resources all `depends_on` the
node pool (directly or transitively) to enforce this ordering within one graph.

## State & CI

- State lives in **Scaleway Object Storage** (S3-compatible, `backend.tf`).
  There is **no state locking** (no DynamoDB equivalent), so both workflows
  share a `concurrency: terraform-state` group to serialize runs. Never run a
  local apply while CI might be applying.
- `cd.yaml`: `plan` runs on every push to `terraform/**`; `apply` runs **only**
  on manual `workflow_dispatch` and is gated by the `production` environment
  (required-reviewer approval).
- `destroy.yaml`: owner-only (`github.actor`) **and** a typed `DESTROY` input.

## Free-tier budget — do not exceed

The defaults sit exactly on the Always-Free caps; changing them silently incurs
charges or breaks `apply`:
- Workers: 2 × `VM.Standard.A1.Flex`, **2 OCPU + 12 GB each** (4 OCPU / 24 GB = full A1 cap).
- Boot volumes: **2 × 100 GB = 200 GB** (full block-storage cap). These disks also back Longhorn.
- A1 is **ARM/aarch64** — `locals.tf` selects an aarch64 worker image; any Helm chart must publish arm64.
- Control plane is `BASIC_CLUSTER` (free); the NLB is the flexible always-free shape.

## Platform layout (`addons.tf`)

Dependency chain matters — edits that reorder it will fail mid-apply:

1. **Longhorn** — set as default StorageClass; OKE's `oci-bv` is demoted
   (annotation) so a class-less PVC can't provision a paid block volume.
2. **Gateway API CRDs** (fetched from the upstream release) — must precede Traefik.
3. **Traefik v3** — Gateway API provider, `replicas == node_count` with
   **required** pod anti-affinity (one per host). Surge is impossible, so the
   update strategy is `maxSurge=0, maxUnavailable=1` — rolls by freeing a host first.
4. **cert-manager** — Let's Encrypt **DNS-01 via Cloudflare**; issues one
   wildcard cert per zone, terminated at the Gateway's `websecure` listener.

`dns.tf` reads Traefik's assigned NLB IP and creates Cloudflare A records for
the app `domains`. `github.tf` exports the kubeconfig + OCI creds as **org**
Actions secrets for downstream app repos. `ssh.tf` generates the worker SSH
keypair (private key → org secret).

## Conventions

- `default_cluster_issuer` defaults to `letsencrypt-staging`; switch to
  `letsencrypt-prod` only after verifying issuance (avoid LE rate limits).
- `cloudflare_dns_api_token` lands in a k8s Secret and therefore in TF state —
  treat state as sensitive.
- Lock `http_ingress_cidr` to Cloudflare ranges to force traffic through the CF
  proxy; `0.0.0.0/0` leaves the NLB directly reachable.
