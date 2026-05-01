## 1. Discovery — capture current cluster state before any scaffold

Conventions are decided (see design.md "Resolved Questions"); discovery is now strictly about capturing the live state we will migrate from.

- [ ] 1.1 Verify Nextcloud namespaces exist for every WOO tenant we plan to migrate: for each `<org>-<env>-reactfront` Application currently in argocd, confirm namespace `<org>-<env>` exists and carries `app.kubernetes.io/part-of: nextcloud-platform`. Any missing pair = blocker (means there is no Nextcloud co-tenant; revisit whether namespace-pairing applies for that tenant).
- [ ] 1.2 Snapshot every existing reactfront Application's full source spec to one file:
  ```bash
  kubectl get applications -n argocd -o yaml \
    | yq '.items[] | select(.metadata.name | test("-reactfront$"))
        | {name: .metadata.name,
           ns_today: .spec.destination.namespace,
           parameters: .spec.source.helm.parameters,
           values: .spec.source.helm.values}' \
    > openspec/changes/bootstrap-react-platform/cluster-state.yaml
  ```
  This file is the ground truth for branding (`pwa.env.GATSBY_*`, theme classname, favicon, etc.). Tenant files are derived from it, not from the bash generator.
- [ ] 1.3 Pick the current semver for `pwa.image.tag` from GHCR (`ghcr.io/conductionnl/woo-website-v2`). Record the chosen tag in this tasks file before scaffolding `common.yaml`.
- [ ] 1.4 Pick the canary tenant. Proposal: `test-mcc-accept` (no branding overrides → cleanest convention test). Confirm with operator before proceeding.

## 2. Repo skeleton — no cluster impact

- [ ] 2.1 Create directory tree under `react-base/`:
  - `react-platform/{argo,platform,values,scripts,docs}/`
  - `react-platform/values/{env,tenants,templates}/`
  - `react-platform/platform/policies/`
  - `charts/`
- [ ] 2.2 Vendor the chart: copy `woo-website-template-apiv2/helm/woo-website/` (refactor branch, current commit) to `react-base/charts/woo-website/`. Verify `helm template ./charts/woo-website` renders cleanly. Record the upstream commit hash in `charts/woo-website/UPSTREAM` so future bumps are traceable.
- [ ] 2.3 Write `react-base/CLAUDE.md`. Mirror Nextcloud-base structure (project overview, common commands, architecture, sync windows, adding-a-tenant). Strip every reference to DB / Redis / PgBouncer / ESO / S3 / RWX storage. Add a "Co-tenancy with Nextcloud" section explaining the shared-namespace model.
- [ ] 2.4 Write `react-base/README.md` (Dutch, same tone as Nextcloud-base; emphasise "2-line tenant" simplicity).
- [ ] 2.5 Initialise `react-base/CHANGELOG.md` with an entry for this scaffold (per global rule: user-owned project requires a changelog).
- [ ] 2.6 Write `react-base/.gitignore`: at minimum `charts/*.tgz`, `**/.DS_Store`, `*.secret.yaml`, `secrets/`, `env.local`, `cluster-state.yaml` if it ends up containing anything sensitive.

## 3. Values layering — encodes platform conventions

- [ ] 3.1 `values/common.yaml`: chart version pin, image registry, `pwa.image.tag: <semver from task 1.3>` (never `latest`), `nodeSelector: {role: prod-nextcloud}`, `nextcloud-only` toleration, ingress `className: nginx`, `strategy: {type: Recreate}`, security context defaults from the chart, upstream base path `/apps/opencatalogi/api`, default theme classname, default `replicaCount`. **No domain or upstream host pattern here — those are env-specific.**
- [ ] 3.2 `values/env/accept.yaml`: `domainSuffix: accept.openwoo.app`, `upstreamHostTemplate: <name>.accept.commonground.nu`, replicas, HPA off, accept-tier resources.
- [ ] 3.3 `values/env/prod.yaml`: `domainSuffix: openwoo.app`, `upstreamHostTemplate: <name>.commonground.nu`, replicas, HPA on, prod-tier resources.
- [ ] 3.4 `values/templates/tenant-template.yaml`: 2-line minimum (`tenant.name`, `tenant.environment`) with commented optional overrides for `branding.*`, `hostname`, `apiBaseUrl`, `wave`.
- [ ] 3.5 Generate `values/tenants/tenant-<name>.yaml` per existing tenant by translating `cluster-state.yaml` (task 1.2): copy any `pwa.env.GATSBY_*` and `NL_DESIGN_THEME_CLASSNAME` into the tenant's `branding` map. Tenants whose live state matches the platform default produce a 2-line file.

## 4. Argo CD — AppProject and ApplicationSet

- [ ] 4.1 Write `argo/projects/react-platform.yaml` (AppProject). Mirror Nextcloud-base AppProject:
  - `sourceRepos`: this repo
  - `destinations`: `namespace: '*-accept'` and `namespace: '*-prod'` on the single cluster server (matches Nextcloud-base destinations exactly, since namespaces are shared)
  - sync windows: Mon–Thu 17:00–07:00 Europe/Amsterdam — *deny* outside the window for any change touching `values/common.yaml`, `values/env/*.yaml`, `argo/`, `platform/`, `charts/`. *Allow* anytime for changes scoped to `values/tenants/`.
- [ ] 4.2 Write `argo/applicationsets/react-tenants.yaml`. Generator: git directory match on `values/tenants/tenant-*.yaml`. Template:
  - `metadata.name: {{ .tenant.name }}-{{ .tenant.environment }}-reactfront`
  - `spec.destination.namespace: {{ .tenant.name }}-{{ .tenant.environment }}` (paired with Nextcloud namespace — see design.md Decision 3)
  - `spec.destination.server`: the single in-cluster server
  - `spec.source.path: charts/woo-website`
  - `spec.source.helm.parameters`: derived `global.domain`, `pwa.upstream.base`, `pwa.upstream.host` from env templates
  - `spec.source.helm.valueFiles`: `[../../values/common.yaml, ../../values/env/{{ .tenant.environment }}.yaml]` plus inline `values:` for tenant branding
- [ ] 4.3 Verify with `helm template` + `kubeconform`: each scaffolded tenant renders cleanly. Diff the rendered manifest against `cluster-state.yaml` for that tenant; the only expected delta is `metadata.namespace` (old `<name>` → new `<name>-<env>`).

## 5. Platform policies — pod-label-scoped, not namespace-label-scoped

- [ ] 5.1 `platform/policies/networkpolicy-react-default-deny.yaml`: deny all ingress and egress for pods labeled `app.kubernetes.io/part-of: react-platform`. **Selects pods, not namespaces** — leaves Nextcloud co-tenant traffic untouched.
- [ ] 5.2 `platform/policies/networkpolicy-react-allow-ingress-controller.yaml`: allow ingress from the ingress-nginx namespace to react pods.
- [ ] 5.3 `platform/policies/networkpolicy-react-allow-egress-public-api.yaml`: allow react pods egress to DNS + the public-internet routable IP for the upstream API hosts. The upstream is *not* the in-cluster Nextcloud pod — the PWA hits the public hostname via ingress, so egress is "anywhere on TCP/443". If we ever switch to in-cluster API access, this rule needs revisiting.
- [ ] 5.4 Verify on canary cut-over (task 8) that the Nextcloud pod in the same namespace shows zero connectivity regression.

## 6. Scripts

- [ ] 6.1 `scripts/validate-values.sh`: required fields per tenant file (`tenant.name`, `tenant.environment` ∈ {accept, prod}). Mirror Nextcloud-base shape minus DB/secret checks.
- [ ] 6.2 `scripts/smoke-checks.sh`: `helm template` every tenant against the chart, pipe through `kubeconform` for schema check. No cluster connection required.
- [ ] 6.3 GitHub Actions workflow `.github/workflows/validate.yaml`: yamllint + smoke-checks + values-validate + gitleaks. Mirror Nextcloud-base validate.yaml minus DB-specific jobs.

## 7. Docs

- [ ] 7.1 `docs/ADDING-TENANT.md`: copy template, edit name + env, commit, push. ApplicationSet auto-detects. Include the namespace-pairing rule (frontend lands in same namespace as Nextcloud co-tenant; that namespace must already exist).
- [ ] 7.2 `docs/ROLLOUTS.md`: sync windows, wave 0 → 1 → 2 → 3 procedure, image-tag bump procedure (platform change → 17:00 window), rollback (revert PR).
- [ ] 7.3 `docs/MIGRATION.md`: per-tenant cut-over runbook from "namespace `<name>`" to "namespace `<name>-<env>`". Lifted from design.md Migration Plan plus concrete `kubectl` commands.

## 8. Canary cut-over — single tenant, in the sync window

- [ ] 8.1 Confirm canary tenant from task 1.4. Verify the target namespace `<name>-<env>` exists and Nextcloud pod is running there.
- [ ] 8.2 Diff `helm template` output of the ApplicationSet-generated Application for this tenant against the live `cluster-state.yaml` row. Resolve every meaningful diff (namespace is expected to differ).
- [ ] 8.3 Wait for the next 17:00–07:00 Europe/Amsterdam window. Announce in the relevant ops channel.
- [ ] 8.4 Capture pre-state: `kubectl get all,ingress,cert -n <old-namespace>` and `kubectl get all,ingress,cert -n <new-namespace>` saved to a timestamped log.
- [ ] 8.5 Delete the standalone Application **with cascade** (default behaviour, not `--cascade=orphan` — we want the workload in the old namespace gone): `kubectl delete application -n argocd <name>-<env>-reactfront`. Confirm Deployment/Service/Ingress in `<old-namespace>` are removed.
- [ ] 8.6 Sync the ApplicationSet — produces an Application with the same name, targeting `<new-namespace>`. Workload is created fresh.
- [ ] 8.7 Wait for cert-manager: `kubectl wait -n <new-namespace> --for=condition=Ready cert/<tls-cert-name> --timeout=5m`. If it times out, check that the Ingress in old namespace is fully gone (host conflict prevents issuance).
- [ ] 8.8 Verify ingress reachable: `curl -I https://<host>` returns 200 with the new TLS cert (check `openssl s_client -connect <host>:443 -servername <host> < /dev/null | openssl x509 -noout -dates`).
- [ ] 8.9 Verify branding survived: curl the page, grep for the expected theme classname / org name from the tenant file.
- [ ] 8.10 Verify Nextcloud co-tenant unaffected: `kubectl get pods -n <new-namespace>` shows Nextcloud pod restart count unchanged from the pre-state log.
- [ ] 8.11 Soak ~24h before any wave-1 cut-over.

## 9. Wave rollout — only after canary soaks

- [ ] 9.1 Wave 1: tenants without custom branding (those whose tenant file is just 2 lines). Repeat steps 8.4–8.10 per tenant inside a single sync window.
- [ ] 9.2 Wave 2: tenants with branding (Almere, etc.). Same procedure; pay extra attention to step 8.9 — verify favicon URL, jumbotron URL, org name match the tenant YAML.
- [ ] 9.3 Wave 3: stragglers and any tenant where step 8.2 produced unresolved diffs.

## 10. Decommission the old path

- [ ] 10.1 Mark `mcc create-react` as deprecated in toolchain CLI help text. Do not remove yet.
- [ ] 10.2 Move `toolchain/woo-application-*.yaml` files to `toolchain/archive/` (keep for one quarter as rollback reference).
- [ ] 10.3 File a follow-up openspec change `mcc-add-react-tenant`: replacement CLI that writes a tenant YAML and opens a PR. **Out of scope for this change.**
