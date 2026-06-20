# Changelog

All notable changes to this repository are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed
- **2026-06-20 — fix(argo): point the react-platform app-of-apps at HEAD (main).**
  `react-platform/argo/applications/root.yaml` `targetRevision`
  `feat/bootstrap-react-platform` → `HEAD`. The live `react-platform` app drives
  the whole `argo/` dir (AppProject + `react-tenants` appset + root itself) and
  self-heals, so manual `kubectl apply` of the appset was reverted to the old
  branch. Cutover needs a ONE-TIME live patch of the app's `targetRevision`
  (app-of-apps reads its own revision from the old branch); after that it's pure
  GitOps on main.
- **2026-06-20 — feat(argo): roll out conduction test/demo frontends + upstream-follows-backend rule.**
  - Added `tenant-conduction-*.yaml` to the generator glob → new WOO frontends
    for `conduction-test` and `conduction-demo` (no legacy app to cut over).
    Frontend hosts derive to `conduction-{test,demo}.accept.openwoo.app`
    (auto DNS via external-dns + TLS via cert-manager); upstream points at the
    real backend `test.conduction.nl` / `demo.conduction.nl`.
  - **New rule:** the frontend upstream host now follows `tenant.hostname` when
    set (external-domain tenants) so frontend and backend never drift; explicit
    `tenant.frontend.upstreamHost` overrides both. Mirrored in `smoke-checks.sh`.
    Only affects tenants with `tenant.hostname` in the glob (conduction); canary
    (no `tenant.hostname`) is unchanged.
  - Frontends use the platform-default woo-website image (no per-tenant pin);
    pin via `tenant.frontend.tag` if needed. (The dev-tagged openwoo *backend*
    apps are a separate concern — the frontend only calls their API.)
  - Smoke-checks: both render clean (9 resources each, kubeconform valid).
- **2026-06-20 — feat(argo): Nextcloud-base becomes the single source of truth for tenants ("Argo ís de watcher").**
  Branch `feat/nc-base-as-tenant-source`. The `react-tenants` ApplicationSet git
  generator now reads `nextcloud-platform/values/tenants/tenant-*.yaml` from
  `codeberg.org/conduction/Nextcloud-base.git` instead of this repo's own
  `values/tenants/`. Adding a Nextcloud tenant auto-creates its co-tenant WOO
  frontend; the frontend fleet is a pure function of the Nextcloud tenant fleet
  (zero drift, no bespoke watcher process). This repo no longer holds per-tenant
  files — removed `values/tenants/tenant-canary-{accept,prod}.yaml` and
  `values/templates/tenant-template.yaml`; added `values/tenants/README.md`.
  - **Schema:** per-tenant frontend config lives in an optional `tenant.frontend:`
    block in the Nextcloud tenant file (`enabled`, `tag`, `host`, `branding`,
    `env`). Opt-out model: absent block → frontend created with platform defaults.
    `tag` is the per-tenant image pin (the "iffy tags" escape hatch for migration).
  - **Derivation:** Nextcloud `tenant.name` already encodes the environment
    (`almere-accept`), so it maps 1:1 to the namespace and the
    `<name>-reactfront` Application name (== legacy `mcc create-react` output);
    the bare org (`almere`) is stripped via `trimSuffix` for the public hostname only.
  - **Gating:** generator glob is canary-only (`tenant-canary-*.yaml`) for this
    phase — flipping the live appset to this branch touches ONLY canary, an
    apples-to-apples test (canary render is identical to the old source).
  - Added `Nextcloud-base.git` to AppProject `react-platform` `sourceRepos`.
  - Updated `scripts/{smoke-checks,validate-values}.sh`: read the Nextcloud-base
    tenant dir (`TENANTS_DIR`/`TENANT_GLOB` overridable), new derivation, drop the
    tenant file from helm `-f` (the appset no longer passes it), validate the
    `frontend:` block.
  - **Deferred to Fase 2:** widen glob to the full fleet + stage the cut-over of
    the 44 legacy Helm-toolchain frontends (`default` project) per
    `docs/MIGRATION.md`; opt-out *exclusion* mechanism for `enabled:false` tenants
    (a git-files generator cannot skip on a nested field — candidate: a
    `frontend.enabled` gate inside the woo-website chart).
  - Merged onto `main` (trunk-based, no PR); `targetRevision` set to `HEAD` for
    the React-base chart/values sources (generator already tracks Nextcloud-base
    `HEAD`). Canary gating is the generator glob, independent of the revision.
- **chore(argo): migrate source GitHub → Codeberg.** GitHub org `ConductionNL`
  is shadowbanned (`react-platform` + canary reactfront apps `SYNC=Unknown`).
  Repointed `repoURL` `github.com/ConductionNL/React-base` →
  `codeberg.org/Conduction/React-base` in `react-platform/argo/projects/react-platform.yaml`,
  `applicationsets/react-tenants.yaml`, `applications/root.yaml`. Public HTTPS,
  no credentials. GitHub kept for rollback.

### Added

- **2026-05-01** — Initial openspec change `bootstrap-react-platform`. Proposal/design/tasks for mirroring the Nextcloud-base GitOps shape onto the WOO PWA: ApplicationSet + layered Helm values (`common.yaml` → `env/*.yaml` → `tenants/tenant-*.yaml`), vendored `woo-website` chart, AppProject sync-window governance. Replaces the `mcc create-react` per-tenant manifest generator. Tenant files become 2 lines (`name`, `environment`) for the common case; namespace pairs with the Nextcloud co-tenant (`<org>-<env>`); image tag pinned to semver in `common.yaml` (no more `latest`); branding migration sources truth from live cluster state. No code or values scaffolded yet — planning docs only. Files: `openspec/changes/bootstrap-react-platform/{.openspec.yaml,proposal.md,design.md,tasks.md}`.
- **2026-05-01** — Document external dependencies in `bootstrap-react-platform`: DNS handled by `cluster-infra/external-dns` (Cloudflare, `policy: sync`, zones `commonground.nu`/`openwoo.app`/`opencatalogi.nl`) — tenant adds/removes auto-create/auto-reap DNS records. TLS via cert-manager + HTTP-01. Recorded in `design.md` (new "External dependencies" subsection), `proposal.md` (Removed from Scope), and `tasks.md` (task 7.1 will surface this in `docs/ADDING-TENANT.md`).
- **2026-05-01** — Scaffold `react-platform/` (openspec phases 2–7). Vendored `charts/woo-website/` from `woo-website-template-apiv2@b1ac4e89` (refactor branch) plus added `templates/networkpolicy.yaml` for pod-label-scoped default-deny + allow-ingress + allow-egress policies. Wrote `react-platform/values/{common,env/accept,env/prod}.yaml` and `templates/tenant-template.yaml` (image pinned to `1.0.0`, `nodeSelector: role: prod-nextcloud`, ingress className `nginx`, security context platform-grade). Wrote AppProject `react-platform` and ApplicationSet `react-tenants` (mirrors Nextcloud-base shape, namespace `<name>-<env>`, Application name `<name>-<env>-reactfront`). Wrote `scripts/{validate-values,smoke-checks}.sh` (smoke-check reproduces ApplicationSet inline values in bash for offline render testing). Wrote `docs/{ADDING-TENANT,ROLLOUTS,MIGRATION}.md`, `CLAUDE.md`, and updated `README.md`. Synthetic tenant `tenant-test-mcc.yaml` added as canary placeholder; smoke-checks pass (9 resources clean). Phase 1 (cluster discovery) and 8–10 (cut-overs) are deferred to live operations.
