# CVVFCM Kubernetes Cluster

Infrastructure-as-code for the **CVVFCM** sailing club's Kubernetes cluster,
running on **Oracle Cloud (OKE) Always-Free tier** and provisioned end-to-end
with **OpenTofu** — cluster, network, ingress, storage, TLS, DNS and telemetry.

This README is the architectural map. For commands, conventions and operational
detail (how to plan/apply, the two-phase bootstrap, free-tier limits), see
[`AGENTS.md`](./AGENTS.md).

## Architecture

### 1. Infrastructure & network topology

Where everything lives: public subnets inside one VCN — control plane, a flexible
NLB, and two ARM workers — fronted by Cloudflare DNS and backed by external SaaS.

```mermaid
flowchart TB
    user(["👤 Club members / Internet"])

    subgraph cf["☁️ Cloudflare"]
      dns["DNS zone cvvfcm.fr<br/>A records → NLB IP"]
    end

    subgraph oci["🟠 Oracle Cloud — Always-Free"]
      igw["Internet Gateway"]
      subgraph vcn["VCN 10.0.0.0/16"]
        subgraph apisub["api subnet · 10.0.0.0/28"]
          cp["OKE control plane<br/>BASIC_CLUSTER · public API :6443"]
        end
        subgraph lbsub["lb subnet · 10.0.2.0/24"]
          nlb["Flexible NLB<br/>:80 / :443 · preserve-source"]
        end
        subgraph wsub["workers subnet · 10.0.1.0/24"]
          w1["Worker 1<br/>A1.Flex · 2 OCPU / 12 GB"]
          w2["Worker 2<br/>A1.Flex · 2 OCPU / 12 GB"]
        end
      end
    end

    subgraph saas["🌐 External services"]
      gc["Grafana Cloud<br/>logs + metrics"]
      scw["Scaleway Object Storage<br/>OpenTofu state"]
      gh["GitHub Actions<br/>CI/CD + org secrets"]
    end

    user --> dns --> igw
    igw --> nlb
    igw -. "kube API" .-> cp
    nlb --> w1 & w2
    cp -. manages .-> w1 & w2
    w1 & w2 -. telemetry .-> gc

    classDef oracle fill:#ff8000,stroke:#cc6600,color:#fff
    classDef cloud fill:#f38020,stroke:#b35900,color:#fff
    classDef ext fill:#1f2937,stroke:#111,color:#fff
    class cp,nlb,w1,w2,igw oracle
    class dns cloud
    class gc,scw,gh ext
```

### 2. Request lifecycle

How an HTTPS request reaches a pod — including the two non-obvious hops: the NLB
preserves the client source IP onto a worker NodePort, and the Gateway listeners
bind Traefik's entrypoints `8000/8443` (not `80/443`).

```mermaid
sequenceDiagram
    autonumber
    participant C as 👤 Client
    participant CF as ☁️ Cloudflare DNS
    participant NLB as 🟠 OCI NLB :443
    participant N as Worker :nodePort
    participant T as Traefik :8443
    participant R as Gateway + HTTPRoute
    participant P as App Pod

    C->>CF: resolve app.cvvfcm.fr
    CF-->>C: NLB public IP
    C->>NLB: HTTPS
    NLB->>N: forward — client source IP preserved
    Note over N: worker SecList opens<br/>nodePort range 30000-32767
    N->>T: kube-proxy → Traefik pod
    T->>T: terminate TLS (wildcard-tls)
    T->>R: match Host + path
    R->>P: Service → Pod
    P-->>C: response
```

### 3. Provisioning & CI/CD

OpenTofu drives four provider groups; state lives in Scaleway Object Storage (no
locking, so runs are serialized via a concurrency group). The first apply is
two-phase: target the cluster + node pool, then the kubernetes/helm/kubectl
providers can authenticate against the live API. `apply` and `destroy` are gated.

```mermaid
flowchart LR
    dev["💻 Local<br/>tofu + .yohan/.env"]
    subgraph ci["🤖 GitHub Actions"]
      plan["plan<br/>on push terraform/**"]
      apply["apply<br/>manual dispatch · prod approval"]
      destroy["destroy<br/>owner + typed DESTROY"]
    end
    state[("Scaleway S3<br/>state · no lock<br/>concurrency: terraform-state")]
    core{{"OpenTofu core"}}
    subgraph prov["Providers"]
      direction LR
      poci["oci"]
      pcf["cloudflare"]
      pgh["github"]
      pk8s["kubernetes · helm · kubectl<br/>exec: oci generate-token"]
    end
    ocir["OCI · VCN · OKE · NLB"]
    cfr["Cloudflare DNS records"]
    ghr["GitHub org secrets<br/>kubeconfig · OCI creds · SSH key"]
    k8sr["In-cluster add-ons"]

    dev --> core
    plan & apply & destroy --> core
    core <--> state
    core --> poci & pcf & pgh & pk8s
    poci --> ocir
    pcf --> cfr
    pgh --> ghr
    pk8s --> k8sr

    classDef store fill:#4f46e5,stroke:#312e81,color:#fff
    class state store
```

### 4. In-cluster platform & observability

Add-on dependency order (node pool → storage / Gateway CRDs / cert-manager →
Traefik → Gateway → app routes), wildcard TLS issued via Let's Encrypt DNS-01,
and the telemetry hop to Grafana Cloud.

```mermaid
flowchart TB
    np["OKE node pool ready"]
    lh["Longhorn — default StorageClass<br/>ns: longhorn-system"]
    crds["Gateway API CRDs v1.5"]
    cmgr["cert-manager + ClusterIssuers<br/>letsencrypt staging / prod<br/>ns: cert-manager"]
    tr["Traefik v3.7<br/>Gateway provider · entrypoints 8000/8443<br/>ns: traefik"]
    gwm["Gateway 'main'<br/>listeners 8000/8443"]
    wc["wildcard-tls · *.cvvfcm.fr"]
    dash["Dashboard IngressRoute<br/>BasicAuth"]
    hc["healthcheck — Caddy + HTTPRoute"]
    mp["meteoprint + HTTPRoute"]
    al["Alloy DaemonSet<br/>ns: alloy"]
    gcloud["☁️ Grafana Cloud"]

    np --> lh & crds & cmgr & al
    crds --> tr
    tr --> gwm
    cmgr -- "DNS-01 via Cloudflare" --> wc
    wc --> gwm
    dash --> tr
    hc & mp -. attach .-> gwm
    al -- "logs + metrics" --> gcloud

    classDef ns fill:#0ea5e9,stroke:#0369a1,color:#fff
    class lh,crds,cmgr,tr,al ns
```

## Components

| Component | Namespace | Role |
|---|---|---|
| OKE cluster | — | Managed Kubernetes control plane (`BASIC_CLUSTER`, free) |
| Worker pool | — | 2× `VM.Standard.A1.Flex` ARM nodes (2 OCPU / 12 GB each) |
| Longhorn | `longhorn-system` | Default StorageClass, replicated across node boot disks |
| Gateway API CRDs | — | Standard channel v1.5 (matched to Traefik v3.7) |
| Traefik | `traefik` | Ingress via Gateway API, TLS termination, dashboard |
| cert-manager | `cert-manager` | Let's Encrypt DNS-01 wildcard cert (`*.cvvfcm.fr`) |
| Grafana Alloy | `alloy` | Logs + metrics collector → Grafana Cloud |
| healthcheck | `healthcheck` | Caddy probe app proving the ingress path |
| meteoprint | `meteoprint` | Application |

External: **Cloudflare** (DNS), **Scaleway Object Storage** (OpenTofu state),
**GitHub Actions** (CI/CD + org-secret export), **Grafana Cloud** (observability).

---

See [`AGENTS.md`](./AGENTS.md) for build/apply commands, the two-phase bootstrap,
free-tier budget limits, and platform conventions.
