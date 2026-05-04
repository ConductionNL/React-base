# React-base

<div align="center">

![React](https://img.shields.io/badge/React-61DAFB?style=for-the-badge&logo=react&logoColor=black)
![Gatsby](https://img.shields.io/badge/Gatsby-663399?style=for-the-badge&logo=gatsby&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![ArgoCD](https://img.shields.io/badge/Argo%20CD-EF7B4D?style=for-the-badge&logo=argo&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-0F1689?style=for-the-badge&logo=helm&logoColor=white)

**Een GitOps-platform voor het uitrollen van meerdere WOO PWA-frontends op Kubernetes**

[Quick Start](#-quick-start) •
[Architectuur](#-architectuur) •
[Tenant toevoegen](#-tenant-toevoegen) •
[Documentatie](#-documentatie)

</div>

---

## ✨ Kenmerken

- 🪶 **Tenant in 2 regels YAML** — alles afgeleid van naam + omgeving
- 🔄 **GitOps-first** — alle config in Git, automatische sync via Argo CD
- 🤝 **Co-tenancy met Nextcloud** — frontend deelt namespace met zijn Nextcloud-backend
- 🌐 **Automatische DNS + TLS** — external-dns + cert-manager doen alles, geen Cloudflare-actie per tenant
- 🎯 **Wave-rollouts** — canary (wave 0) eerst, dan progressive
- 🔒 **NetworkPolicies meegeleverd** — default-deny per pod, geen impact op co-tenants

## 🏗️ Architectuur

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Kubernetes Cluster                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────────────┐  ┌──────────────────────────┐                 │
│  │ ns: almere-accept        │  │ ns: zuiddrecht-prod      │   ...           │
│  │  ┌────────────────────┐  │  │  ┌────────────────────┐  │                 │
│  │  │ Nextcloud (BE)     │  │  │  │ Nextcloud (BE)     │  │                 │
│  │  │ Nextcloud-base ↑   │  │  │  │ Nextcloud-base ↑   │  │                 │
│  │  └────────────────────┘  │  │  └────────────────────┘  │                 │
│  │  ┌────────────────────┐  │  │  ┌────────────────────┐  │                 │
│  │  │ WOO PWA  (FE)      │  │  │  │ WOO PWA  (FE)      │  │                 │
│  │  │ React-base ↑       │  │  │  │ React-base ↑       │  │                 │
│  │  └────────────────────┘  │  │  └────────────────────┘  │                 │
│  └──────────────────────────┘  └──────────────────────────┘                 │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │  Cluster-infra: external-dns (Cloudflare), cert-manager, ingress-nginx  ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                              ┌─────────────┐
                              │  Cloudflare │ ← auto-sync via external-dns
                              │  (DNS only) │
                              └─────────────┘
```

### Waarom dit platform?

Tot nu toe werd elke WOO PWA uitgerold via `mcc create-react <org> <env>`,
een bash-script dat per tenant een ~50-regel Argo Application-manifest
genereerde met alle conventies hardcoded (domein, upstream, nodepool, TLS).
Resultaat: convention-changes raakten *elke* tenant, drift was onzichtbaar,
en "tenant toevoegen" was geen pure GitOps-flow.

Dit platform spiegelt `Nextcloud-base`: één ApplicationSet, gelaagde
Helm-values, één wijziging in `common.yaml` raakt iedereen tegelijk via een
gepland sync window.

## 📁 Repository structuur

```
react-base/
├── charts/
│   └── woo-website/                # Vendored Helm chart (zie UPSTREAM)
├── react-platform/
│   ├── argo/
│   │   ├── projects/               # AppProject met sync windows
│   │   └── applicationsets/        # Tenant-generator
│   ├── platform/
│   │   └── policies/               # README — policies leven in chart-templates
│   ├── values/
│   │   ├── common.yaml             # Platform-defaults voor alle tenants
│   │   ├── env/                    # accept.yaml, prod.yaml
│   │   ├── tenants/                # tenant-<naam>.yaml (per tenant)
│   │   └── templates/              # tenant-template.yaml
│   ├── scripts/                    # validate-values.sh, smoke-checks.sh
│   └── docs/                       # ADDING-TENANT, ROLLOUTS, MIGRATION
├── openspec/
│   └── changes/
│       └── bootstrap-react-platform/   # Design proposal voor dit platform
├── CLAUDE.md
├── CHANGELOG.md
└── README.md (dit bestand)
```

## 🚀 Quick Start

### Vereisten
- Kubernetes 1.28+
- Argo CD geïnstalleerd
- `cluster-infra` repo deployed (external-dns + cert-manager + ingress-nginx)
- DNS-zones `commonground.nu` / `openwoo.app` / `opencatalogi.nl` op Cloudflare
- Tenant-namespace bestaat al via `Nextcloud-base`

### 1. Clone
```bash
git clone https://github.com/ConductionNL/React-base.git
cd React-base
```

### 2. Apply AppProject + ApplicationSet
```bash
kubectl apply -f react-platform/argo/projects/react-platform.yaml
kubectl apply -f react-platform/argo/applicationsets/react-tenants.yaml
```

### 3. Eerste tenant
Zie [Tenant toevoegen](#-tenant-toevoegen) hieronder.

## 🪶 Tenant toevoegen

```yaml
# react-platform/values/tenants/tenant-mijn-org.yaml
tenant:
  name: mijn-org
  environment: accept
```

Dat is genoeg. Commit + push + merge → ApplicationSet pakt het op,
external-dns maakt het Cloudflare-record, cert-manager regelt TLS.

Met branding:

```yaml
tenant:
  name: almere
  environment: accept
  branding:
    organisationName: "Gemeente Almere"
    themeClassname: almere-theme
    footerHideLogo: true
    jumbotronImageUrl: "https://..."
    faviconUrl: "data:image/png;base64,..."
```

Voor de volledige walkthrough en validatie-stappen: zie
[`react-platform/docs/ADDING-TENANT.md`](react-platform/docs/ADDING-TENANT.md).

## 🌐 Hostname-conventies

| Omgeving | Frontend hostname | Upstream API host |
|---|---|---|
| `accept` | `<naam>.accept.openwoo.app` | `<naam>.accept.commonground.nu` |
| `prod`   | `<naam>.openwoo.app`        | `<naam>.commonground.nu` |

Override per tenant via `tenant.hostname` of `tenant.apiBaseUrl` (zelden nodig).

## 📚 Documentatie

| Document | Onderwerp |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | Architectuur en regels — primaire referentie |
| [`react-platform/docs/ADDING-TENANT.md`](react-platform/docs/ADDING-TENANT.md) | Tenant toevoegen, validatie, removal |
| [`react-platform/docs/ROLLOUTS.md`](react-platform/docs/ROLLOUTS.md) | Sync windows, image-bumps, wave-volgorde, rollback |
| [`react-platform/docs/MIGRATION.md`](react-platform/docs/MIGRATION.md) | Cut-over van losse Applications naar deze ApplicationSet |
| [`openspec/changes/bootstrap-react-platform/`](openspec/changes/bootstrap-react-platform/) | Design proposal en taken |

## 🔧 Validatie

```bash
./react-platform/scripts/validate-values.sh    # vereiste velden + filename
./react-platform/scripts/smoke-checks.sh       # helm template + kubeconform
```

## 📝 License

Onder de MIT License — zie LICENSE.

---

<div align="center">
  <sub>Built voor de CommonGround community</sub>
</div>
