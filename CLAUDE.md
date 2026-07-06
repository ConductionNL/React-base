# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **GitOps platform** for deploying multiple isolated WOO PWA frontends (React/Gatsby) on Kubernetes using Argo CD. It is the **frontend equivalent of `Nextcloud-base`**: same multi-tenant ApplicationSet shape, same wave-based rollouts, same AppProject sync-window governance — minus everything a static frontend doesn't need (no DB, no Redis, no PgBouncer, no External Secrets, no persistent storage).

Each WOO PWA tenant lives in the **same namespace as its Nextcloud co-tenant** (e.g. `almere-accept`, `almere-prod`). The frontend pod and the Nextcloud backend share a namespace per (org, env) tuple.

## Common Commands

### Local validation (before commit)
```bash
./react-platform/scripts/validate-values.sh   # required-field check on tenant files
./react-platform/scripts/smoke-checks.sh      # helm template + kubeconform on every tenant
```

### Required local tools
`helm`, `kubeconform`, `yq` (mikefarah)

## Architecture

### Layered Helm values (3-file merge per tenant)
ApplicationSet `react-tenants` composes values in this order:
1. `react-platform/values/common.yaml` — base config for every tenant on every cluster (image, security, nodepool, ingress class)
2. `react-platform/values/env/{accept,prod}.yaml` — environment-specific overrides (replicas, HPA, resources)
3. `react-platform/values/tenants/tenant-<name>.yaml` — per-tenant: name, environment, optional branding

Plus an inline `values:` block computed by the ApplicationSet template that derives:
- `global.domain` — `<name>.openwoo.app` (prod) or `<name>.accept.openwoo.app` (accept)
- `pwa.upstream.host` and `pwa.upstream.base` — `<name>.commonground.nu` etc.
- TLS secret name: `<name>-<env>-tls`
- `commonLabels` including `app.kubernetes.io/part-of: react-platform` for NetworkPolicy targeting
- All branding env vars from `tenant.branding`

### Tenant definition pattern
Two lines is the common case:
```yaml
tenant:
  name: test-mcc
  environment: accept
```

With branding (Almere-style):
```yaml
tenant:
  name: almere
  environment: accept
  branding:
    organisationName: "Gemeente Almere"
    themeClassname: almere-theme
    footerHideLogo: true
    jumbotronImageUrl: "https://..."
    faviconUrl: "..."
```

### Key directories
- `charts/woo-website/` — vendored Helm chart from `woo-website-template-apiv2`. See `charts/woo-website/UPSTREAM` for the sync point and react-base divergences.
- `react-platform/argo/` — AppProject (`react-platform`) and ApplicationSet (`react-tenants`)
- `react-platform/values/` — common, env, tenants, templates
- `react-platform/scripts/` — `validate-values.sh`, `smoke-checks.sh`
- `docs/` — `ADDING-TENANT.md`, `ROLLOUTS.md`, `MIGRATION.md`
- `openspec/changes/` — design proposals (see `bootstrap-react-platform/` for the bootstrap)

### Namespace convention
Namespace = `<tenant.name>-<tenant.environment>`. Paired with the Nextcloud co-tenant managed by `Nextcloud-base`. The namespace is **not** auto-created by this repo's ApplicationSet — it must already exist via Nextcloud-base before the first sync of a frontend tenant.

### Co-tenancy with Nextcloud
The frontend pod and Nextcloud pod share a namespace per (org, env). Two consequences:
- **NetworkPolicies are pod-label scoped** (`app.kubernetes.io/part-of: react-platform`) — they don't relabel the namespace and don't interfere with Nextcloud-base's namespace-label-scoped policies.
- **Namespace label stays `nextcloud-platform`**. Don't change it; this repo's NetworkPolicies don't depend on it.

### Sync windows (governance)
The AppProject blocks platform-level syncs during weekday office hours (07:00–17:00 Europe/Amsterdam). Operational rule is stricter:

- **Platform changes** (`values/common.yaml`, `values/env/*.yaml`, `argo/`, `charts/`): Mon–Thu 17:00–07:00 only. Never on Fri evenings, Saturdays, or Sundays — unless mwest2020 explicitly approves. Image-tag bumps count as platform changes.
- **Tenant config additions** (`values/tenants/` only): allowed at any time.
- **Canary (wave 0)**: syncs first in every rollout; validate before allowing other waves to proceed.

### External dependencies (not owned by this repo)
- **DNS**: `cluster-infra/external-dns` runs cluster-wide with the Cloudflare provider, `policy: sync`, watches `Ingress` resources in `commonground.nu`/`openwoo.app`/`opencatalogi.nl` zones. Tenant Ingress creation/deletion auto-creates and auto-reaps the DNS record. **Operators never touch Cloudflare to add or remove a tenant.**
- **TLS**: cert-manager via HTTP-01. Cloudflare proxy is intentionally off in `cluster-infra` so HTTP-01 challenges work. Don't enable proxy.
- **Ingress controller**: ingress-nginx in namespace `ingress-nginx` (referenced by the chart's `networkPolicy.ingressNamespace` value).

## CI/CD pipeline

GitHub Actions on every push/PR (`.github/workflows/validate.yaml` — TODO, task 6.3 in openspec):

| Job | Blocking? | What it checks |
|---|---|---|
| YAML lint | Yes | yamllint, sane line lengths |
| Values validation | Yes | `validate-values.sh` |
| Helm + kubeconform | Yes | `smoke-checks.sh` |
| Secret scanning | Yes | gitleaks |

## Vendored chart

`charts/woo-website/` is a pinned copy of `woo-website-template-apiv2/helm/woo-website` at a specific upstream commit (see `charts/woo-website/UPSTREAM`). Divergences from upstream:

- `templates/networkpolicy.yaml` — added by react-base (pod-label-scoped NetworkPolicies)
- `values.yaml` — added `networkPolicy.{enabled,ingressNamespace}` block

Bumping the vendored chart is a platform-level change (sync window applies).

## Adding a new tenant

See `docs/ADDING-TENANT.md`. Short version: copy template, edit name + environment, commit, push. ApplicationSet picks it up on next sync. DNS, TLS, NetworkPolicies, and namespace co-tenancy are all automatic.

## Migration from old standalone Applications

See `docs/MIGRATION.md`. Per-tenant cut-over with 1–3 minutes of downtime, inside the sync window. Canary (`test-mcc-accept`) first, soak 24h, then waves.

## Resource policy

Static nginx — tiny baseline. `common.yaml` ships `cpu: 50m/500m`, `memory: 64Mi/256Mi`. Prod env bumps the limit ceiling slightly. No need for per-tenant resource overrides unless a specific tenant has unusual traffic.

## What this repo deliberately does NOT have

- No database (frontend serves only public content)
- No Redis or PgBouncer (no shared cache, no DB connections)
- No External Secrets Operator (no tenant secrets)
- No PVCs or StorageClasses (image is self-contained)
- No `create-tenant-secret.sh` script (nothing to create)
- No S3 storage layer (no user data)

If any of those become necessary later, prefer adding them via a new openspec change rather than expanding this scaffold organically.

## Operational gotchas

- **`pwa.image.tag: latest` is never used.** Tag is pinned in `common.yaml`. Bumping = platform change = sync window applies.
- **Namespace must exist before first sync.** Frontend ApplicationSet does not create namespaces — Nextcloud-base does. If a frontend tenant exists without a Nextcloud co-tenant, create the namespace manually with `app.kubernetes.io/part-of: nextcloud-platform` label.
- **Don't enable Cloudflare proxy** for any zone external-dns manages — it breaks cert-manager HTTP-01.
- **NetworkPolicies select pods, not namespaces.** Don't relabel the namespace expecting policy changes to follow; they won't.
