## Why

WOO PWA tenants are deployed today via `mcc create-react <org> <env>`, which shells out to `toolchain/scripts/deployment/create_react.sh`. The script generates a per-tenant Argo CD Application manifest with all conventions hardcoded in bash:

- Domain pattern (`<org>.openwoo.app` / `<org>.accept.openwoo.app`)
- Upstream API host (`<org>.commonground.nu` / `<org>.accept.commonground.nu`) and base path (`/apps/opencatalogi/api`)
- Node placement (`role: prod-nextcloud` + `nextcloud-only` toleration)
- Ingress class, TLS secret name, deploy strategy, image tag

Each generated manifest is ~50 lines that mostly repeat platform convention. Consequences:

- **Convention changes are O(N)**: moving frontends to a different nodepool, switching ingress class, or changing the domain suffix requires regenerating every tenant manifest.
- **No drift detection**: there is no shared `common.yaml` defining "what every WOO frontend should look like." A platform-wide fix can pass review for one tenant and silently miss the others.
- **Adding a tenant is not pure GitOps**: the CLI must reach the cluster (`kubectl apply` / `argocd app create`) — there is no PR-only path.
- **The static frontend has no real reason for any of this complexity** — it has no DB, no shared cache, no secrets, and no per-tenant state.

`Nextcloud-base` already solves the exact same shape for Nextcloud tenants (multi-tenant GitOps, layered Helm values, ApplicationSet, wave-based rollouts). Mirror it for the WOO PWA, minus everything a static page does not need (Redis, PgBouncer, ESO, DB layer, S3 storage class, RWX storage).

## What Changes

- New repo skeleton at `react-base/`:
  - `react-platform/argo/` — `ApplicationSet` (one Application per `values/tenants/tenant-*.yaml`) + `AppProject` with sync-window governance mirrored from Nextcloud-base
  - `react-platform/platform/policies/` — NetworkPolicies (default-deny + allow-ingress-controller + allow-egress to public API hosts)
  - `react-platform/values/common.yaml` — chart pin, image, nodeSelector/tolerations, ingress className, deploy strategy, security context, upstream base path, default theme classname
  - `react-platform/values/env/{accept,prod}.yaml` — `domainSuffix`, `upstreamHostTemplate`, replicas, HPA on/off, resources
  - `react-platform/values/tenants/tenant-*.yaml` — minimal per-tenant: `name`, `environment`, optional `branding`/`hostname`/`apiBaseUrl` overrides
  - `react-platform/values/templates/tenant-template.yaml` — copy-paste starting point
  - `react-platform/scripts/` — `validate-values.sh`, `smoke-checks.sh` (helm template + kubeconform). No secret scripts (frontends have none).
  - `react-platform/docs/` — `ADDING-TENANT.md`, `ROLLOUTS.md`
- `charts/woo-website/` — vendored copy of the existing chart from `woo-website-template-apiv2/helm/woo-website` (locked alongside the platform; can flip to OCI registry later)
- `openspec/changes/` — this proposal
- `CLAUDE.md`, `README.md`, `CHANGELOG.md`
- ApplicationSet template auto-derives, per tenant: Application name (`<name>-<env>-reactfront` — matches today, no rename), namespace (`<name>-<env>` — **paired with the Nextcloud namespace; this is a namespace migration from today's bare-name pattern**), hostname, upstream host, upstream base, TLS secret name, wave (default `"1"`)
- Image tag pinned to a semver in `common.yaml` — never `latest`. Image bumps are platform-wide changes and respect the AppProject sync window.

## Capabilities

### New Capabilities

- `tenant-as-data`: a tenant is a 2-line YAML file (name + environment). Branding/hostname/API overrides only set if non-default.
- `wave-rollouts`: canary (wave 0) syncs first, validate, then wave 1+. Mirrors Nextcloud-base.
- `policy-baseline`: NetworkPolicies enforce default-deny + ingress-controller-only ingress + egress to upstream API hosts only.

### Removed from Scope

- `secrets`: the WOO PWA serves only public content. No tenant secrets, no ESO, no `create-tenant-secret.sh`.
- `shared-platform-services`: no Redis, no PgBouncer, no DB layer files. Static nginx pod has no shared state.
- `storage`: no PVC, no StorageClass change. Image is self-contained; runtime config is a small ConfigMap written by the chart.
- `dns`: handled by `cluster-infra/external-dns` (Cloudflare provider, `policy: sync`, zones `commonground.nu`/`openwoo.app`/`opencatalogi.nl`). Tenant Ingress creation/deletion auto-creates and auto-reaps the DNS record — operators never touch Cloudflare to add a tenant.
- `tls`: cert-manager + HTTP-01, already wired in `cluster-infra`. No per-tenant cert configuration in this repo.

## Impact

- **New repo**: `react-base/` (currently empty except `README.md`). User-owned — `CHANGELOG.md` required per global rule.
- **Argo CD**: new `AppProject` `react-platform`, new `ApplicationSet` `react-tenants`. Independent from `nextcloud-platform` project — separate RBAC, separate sync windows.
- **Existing per-tenant manifests** in `toolchain/woo-application-*.yaml` and cluster-side Applications named `<name>-<env>-reactfront`: superseded by ApplicationSet-managed Applications with the same names but a **different target namespace** (`<name>-<env>` instead of `<name>`). Cut-over per tenant has 1–3 minutes of downtime: delete old Application + workload in `<name>` namespace, ApplicationSet creates fresh in `<name>-<env>`, cert-manager re-issues TLS. Run inside the sync window. Start with canary.
- **Co-tenancy with Nextcloud**: WOO frontend pods will share namespaces with their Nextcloud upstreams. Namespace label stays `nextcloud-platform`; react NetworkPolicies select pods by `app.kubernetes.io/part-of: react-platform` pod label. No collision with Nextcloud's namespace-label-based policies.
- **`mcc create-react` CLI**: deprecated. Optional follow-up: replace with a `mcc add-react-tenant` that writes `tenant-<name>.yaml` and opens a PR, but **not in scope for this change** — the new flow is "copy template, commit, push."
- **Cluster infra**: no changes. No new StorageClasses, no new platform services, no namespace pre-bootstrap.
- **`charts/woo-website`**: vendored copy. Upstream `woo-website-template-apiv2` continues to publish images; the chart there is the source we vendor.
