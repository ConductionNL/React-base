## Context

WOO PWA tenants today are deployed via `mcc create-react <org> <env>`, which generates a stand-alone Argo CD Application manifest from `toolchain/scripts/deployment/create_react.sh`. The script encodes platform conventions (domain suffixes, upstream host pattern, nodepool placement, ingress, TLS) directly in bash. Each tenant manifest is ~50 lines, and platform-wide convention changes require regenerating every manifest.

`Nextcloud-base` already runs the same shape correctly for Nextcloud tenants: ApplicationSet, layered Helm values (`common.yaml` → `env/*.yaml` → `tenants/tenant-*.yaml`), wave-based rollouts, AppProject sync-window governance. The WOO PWA needs the same — minus everything a static page does not have:

- No database — no `db/` values layer
- No shared cache, no shared connection pooler — no Redis, no PgBouncer
- No tenant secrets — no External Secrets Operator, no fallback secret generator
- No persistent storage — image is self-contained; runtime config is a small ConfigMap written by the existing chart

The Helm chart `helm/woo-website` in `woo-website-template-apiv2` is already platform-grade (non-root, capability drop, explicit probes, dedicated SA, resource limits). Its `values.yaml` even names react-base in a comment as the intended platform layer. The chart does not need to change for this proposal.

## Goals / Non-Goals

**Goals:**
- A two-line tenant file (`name`, `environment`) is sufficient for the common case. Branding/hostname/API overrides are optional.
- Platform conventions (nodepool, ingress, TLS naming, upstream API base path) live exactly once, in `common.yaml` or `env/*.yaml`. Changing them is a single PR.
- Adding a tenant is pure GitOps: copy template, edit ~2–10 lines, commit, push. No CLI, no cluster access required.
- The Application resource produced by the ApplicationSet is byte-equivalent (name, namespace, parameters, values) to what the bash script produces today, so cut-over per tenant is a no-op data-wise.
- Sync-window and AppProject governance mirror Nextcloud-base — independent project, independent windows, but identical policy shape.

**Non-Goals:**
- Migrating tenant data — a static frontend has no per-tenant state.
- Replacing the upstream chart — `helm/woo-website` stays as-is; we vendor a copy.
- Replacing `mcc` CLI — the create-react command is deprecated by this proposal but its replacement (a tenant-file generator) is a follow-up change.
- Changing the nodepool placement — staying on `role: prod-nextcloud` is status quo. A separate openspec change can move frontends off the Nextcloud nodepool later.
- Adding auth — the PWA serves public content. Any future auth is a per-tenant opt-in flag and is not in scope here.

## Decisions

### Decision 1: ApplicationSet over per-Application generator

**Choice**: a single `ApplicationSet` named `react-tenants` watches `values/tenants/tenant-*.yaml` and generates one Application per file. Application name, namespace, parameters, and inline `values:` are templated from the tenant file plus `common.yaml` and `env/*.yaml`.

**Alternatives**:
- Keep the bash generator, just version-control the output: still suffers from convention drift and is not GitOps for "add a tenant."
- Per-tenant Application files in Git, no ApplicationSet: works but every platform change still touches every tenant file.

**Why ApplicationSet wins**: the value layering is the single source of truth. Convention changes are one-PR. The upstream chart is unchanged. This is exactly the Nextcloud-base shape, already proven on this cluster.

### Decision 2: Vendor the chart at `react-base/charts/woo-website/`

**Choice**: copy `woo-website-template-apiv2/helm/woo-website/` into `react-base/charts/woo-website/`. The ApplicationSet sources the chart from `react-base` itself, not from the upstream repo.

**Alternatives**:
- Helm chart dependency pointing at upstream repo URL: requires the upstream repo to be a Helm chart registry or pinned by commit. Today's manifests pin `targetRevision: main`, which is drift-prone.
- OCI registry: cleaner long-term, but requires CI/CD on `woo-website-template-apiv2` to publish — out of scope.

**Why vendor wins**: audit trail is one repo. Chart and platform values move together in a single PR. We can flip to OCI once upstream publishes; the change is local to `common.yaml` and the ApplicationSet `source:`.

### Decision 3: Pair the frontend namespace with the Nextcloud namespace

**Choice**: ApplicationSet templates produce `name: <tenant.name>-<tenant.environment>-reactfront` (matches today) and `destination.namespace: <tenant.name>-<tenant.environment>` — i.e. the WOO PWA pod lives in the **same** namespace as the corresponding Nextcloud tenant (`almere-accept`, `almere-prod`, etc.). Today's manifests put the frontend in a bare `<tenant.name>` namespace; that pattern is dropped.

**Why**: co-locating the frontend with its upstream Nextcloud aligns the operational mental model — one namespace per (org, env) tuple, regardless of stack layer. Diagnostics, RBAC, quotas, and netpols become tractable per (org, env) rather than per technology. Application *name* is unchanged so monitoring and Argo dashboards keep their identifiers.

**Consequence — this is a namespace migration per tenant, not a re-adoption.** The Deployment/Service/Ingress today live in `<tenant.name>`. After cut-over they live in `<tenant.name>-<tenant.environment>`. Argo CD cannot move resources across namespaces; cut-over is "delete in old namespace, create in new namespace," with brief downtime per tenant. See Migration Plan.

### Decision 4: Co-tenancy with Nextcloud — pod-level labels, not namespace-level

**Choice**: the Nextcloud platform labels namespaces `app.kubernetes.io/part-of: nextcloud-platform` and that label drives its NetworkPolicies. The react platform does **not** relabel the namespace. Instead, react NetworkPolicies select pods by **pod label** `app.kubernetes.io/part-of: react-platform`. Both platforms can coexist in the same namespace without policy collisions.

**Why**: rewriting the namespace label would break Nextcloud's NetworkPolicies. Selecting by pod label scopes each platform's policies to its own pods only; cross-platform traffic (frontend → its own Nextcloud upstream) goes via the public ingress, not pod-to-pod, so no special intra-namespace allow is needed.

### Decision 5: Image tag pinned to semver in `common.yaml` — never `latest`

**Choice**: `common.yaml` carries `pwa.image.tag: <semver>`. Bumping the tag is a platform-wide change. Today's `latest` is dropped on bootstrap; an explicit current semver is pinned.

**Why**: `latest` is a drift source — pods restarted at different times can run different code. Pinning in `common.yaml` means every tenant runs the same version, and version rollouts are explicit, reviewable PRs. Per the AppProject sync-window policy, image bumps fall under "platform changes" and only sync Mon–Thu 17:00–07:00 Europe/Amsterdam — they affect every tenant.

### Decision 6: Keep current node placement in `common.yaml`

**Choice**: `nodeSelector: {role: prod-nextcloud}` and the `nextcloud-only` toleration go into `common.yaml` verbatim. Frontends continue to schedule on the Nextcloud nodepool.

**Why**: status quo, predictable, no infra change. Reinforced by Decision 3 — frontend pods now live in the same namespace as their Nextcloud upstream, and scheduling them on the same nodepool is consistent with that shape. Filing a separate openspec change later (`react-frontends-off-nextcloud-nodepool`) is the right place if we ever want to split them.

### Decision 7: Sync-window governance mirrors Nextcloud-base, separate AppProject

**Choice**: a new AppProject `react-platform` enforces the same Mon–Thu 17:00–07:00 Europe/Amsterdam window for platform-level changes. Tenant-config additions (`values/tenants/` only) are unrestricted. Wave-0 (canary) syncs first. Image-tag bumps in `common.yaml` count as platform-level changes and fall inside the window.

**Why**: the policy is sound for any GitOps platform; copying it gives us familiar guardrails. Independent project means an outage on the WOO platform cannot pause Nextcloud syncs and vice versa. AppProject `destinations` must include all `<tenant.name>-<tenant.environment>` namespaces — exactly the same list Nextcloud-base's project allows, since the namespaces are shared.

## Risks / Trade-offs

| Risk | Severity | Mitigation |
|---|---|---|
| Per-tenant downtime during namespace migration (delete in old ns → create in new ns) | Medium | Schedule cut-over inside the 17:00–07:00 window; cert-manager re-issues TLS automatically; canary tenant first proves the procedure. Static page → no session/data loss, just a brief 5xx during reconcile. |
| TLS cert re-issue rate-limit (Let's Encrypt 5/week per host) if a tenant cut-over fails repeatedly | Low | Use staging issuer for canary's first attempt; only switch to prod issuer once pattern is proven. Stagger waves so worst case is one cert per host per week. |
| New Ingress in new namespace conflicts with old Ingress on same hostname mid-migration | Medium | Cut-over deletes old Application (and its Ingress) **before** the ApplicationSet syncs; serialise per tenant. Brief window where neither Ingress claims the host is intentional. |
| Co-tenancy with Nextcloud breaks Nextcloud's NetworkPolicies | Medium | Decision 4 — keep namespace label `nextcloud-platform`; react policies select pods by `app.kubernetes.io/part-of: react-platform` pod label only. Verify on canary cut-over that Nextcloud pod traffic is unaffected. |
| Vendored chart drifts from upstream | Low | `charts/woo-website/` carries the upstream Chart.yaml `version`; bumping is a deliberate PR. Drift is the *point* — we want platform-controlled rollouts. |
| Convention change in `common.yaml` ripples through all tenants at once (image bump, nodepool change) | Medium | Sync-window restricts platform changes to off-hours; canary syncs first; wave-based rollout limits blast radius. |
| Existing branding hand-edited into live Applications is lost on cut-over | High → Low after task 1.3 | Source of truth for branding is the live cluster (`kubectl get application -o yaml`). Task 1.3 dumps every tenant's `helm.values` before scaffolding any tenant file. |

## Migration Plan

State to migrate per tenant: one standalone Argo CD Application named `<name>-<env>-reactfront`, plus its Deployment/Service/Ingress in namespace `<name>`. Move target: same Application name, but managed by the new ApplicationSet, with workload running in namespace `<name>-<env>` (the existing Nextcloud namespace).

There is no per-tenant data to migrate — the page is static, served from the image, with runtime config from a ConfigMap.

Per-tenant cut-over (start with canary, inside the 17:00–07:00 sync window):
1. Verify the Nextcloud namespace `<name>-<env>` already exists and is labeled `app.kubernetes.io/part-of: nextcloud-platform`. (It will, for any tenant that has a Nextcloud counterpart in that env.)
2. Create `values/tenants/tenant-<name>.yaml`. Branding comes from the live cluster Application (task 1.3), not from the generator script — anything hand-edited post-`create_react.sh` lives only in the cluster.
3. Run `./scripts/smoke-checks.sh` and visually diff the rendered manifest against the live Application's `spec.source.helm.values`. Resolve every diff before proceeding.
4. Delete the standalone Application **with cascade**: `kubectl delete application -n argocd <name>-<env>-reactfront` (default cascade — removes Deployment, Service, Ingress in old namespace `<name>`). The hostname is briefly unclaimed.
5. Sync the ApplicationSet — produces an Application with the same name targeting namespace `<name>-<env>`. Resources are created fresh.
6. cert-manager re-issues TLS for the same hostname into the new namespace. Wait for `kubectl get cert -n <name>-<env>` to show Ready=True.
7. Verify ingress is reachable, Application is Healthy/Synced, branding is intact (curl the page, check theme classname / org name).
8. Verify Nextcloud co-tenant pod is unaffected: `kubectl get pods -n <name>-<env>` and check Nextcloud pod restart count is unchanged.
9. Move to next tenant.

**Total downtime per tenant**: typically 1–3 minutes (delete → recreate → TLS issuance). Acceptable for the static frontend during a sync window.

**Rollback per tenant**: re-apply the original Application manifest from `toolchain/woo-application-<name>-<env>.yaml` (which still targets namespace `<name>`) and remove `tenant-<name>.yaml` from `values/tenants/`. The ApplicationSet stops managing it and the standalone Application is back. Old TLS in the original namespace will need to be re-issued; cert-manager handles this.

## Resolved Questions

All four open questions from the initial draft are answered:

1. **Namespace convention**: pair with the Nextcloud namespace — `<tenant.name>-<tenant.environment>` (e.g. `almere-accept`, `almere-prod`). The bare-name namespace pattern in today's manifests is dropped on cut-over. (See Decision 3.)
2. **Cluster topology**: one cluster hosts both accept and prod, separated by namespace. ApplicationSet `destination.server` is a single value in the template.
3. **Image tag**: never `latest`. Pin to current semver in `common.yaml`. Image-tag bumps are platform-level changes and respect the 17:00–07:00 sync window. (See Decision 5.)
4. **Branding source-of-truth**: the live cluster's `kubectl get application -o yaml` is authoritative. Task 1.3 dumps every tenant's `spec.source.helm.values` and writes the result into the per-tenant YAML before any cut-over. (See Risks table.)
