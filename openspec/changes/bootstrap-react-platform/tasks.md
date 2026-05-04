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

- [x] 2.1 Create directory tree under `react-base/`.
- [x] 2.2 Vendor the chart at upstream commit `b1ac4e89` (refactor/platform-grade-cleanup branch). UPSTREAM file records sync point + react-base divergences (added `templates/networkpolicy.yaml`, added `networkPolicy` block in `values.yaml`).
- [x] 2.3 `react-base/CLAUDE.md` written. Mirrors Nextcloud-base structure, strips DB/Redis/PgBouncer/ESO/storage, adds Co-tenancy with Nextcloud section.
- [x] 2.4 `react-base/README.md` written (Dutch, mirrors Nextcloud-base tone, emphasises 2-line tenant).
- [x] 2.5 `react-base/CHANGELOG.md` initialised with bootstrap entry.
- [x] 2.6 `react-base/.gitignore` covers all required patterns plus `cluster-state.yaml`.

## 3. Values layering — encodes platform conventions

- [x] 3.1 `values/common.yaml` written. Image pinned to `1.0.0` (TODO: verify against GHCR — task 1.3). Discovery: today's `strategy: {type: Recreate}` is dead config (chart Deployment has no `strategy` block, silently ignored). Default RollingUpdate is preserved (better for static frontend). Includes `networkPolicy.{enabled,ingressNamespace}` toggle for chart-shipped policies. Domain logic is **not** here — moved to ApplicationSet template.
- [x] 3.2 `values/env/accept.yaml` written (replicaCount: 1, autoscaling off).
- [x] 3.3 `values/env/prod.yaml` written (replicaCount: 2, HPA enabled, modest limits bump).
- [x] 3.4 `values/templates/tenant-template.yaml` written. 2-line minimum + commented `branding`, `wave`, `hostname`, `apiBaseUrl`, `env` overrides.
- [ ] 3.5 Generate per-tenant files from `cluster-state.yaml` (depends on task 1.2 — deferred to live operations). Synthetic `tenant-test-mcc.yaml` added now as canary placeholder.

## 4. Argo CD — AppProject and ApplicationSet

- [x] 4.1 Write `argo/projects/react-platform.yaml` (AppProject). Mirror Nextcloud-base AppProject:
  - `sourceRepos`: this repo
  - `destinations`: `namespace: '*-accept'` and `namespace: '*-prod'` on the single cluster server (matches Nextcloud-base destinations exactly, since namespaces are shared)
  - sync windows: Mon–Thu 17:00–07:00 Europe/Amsterdam — *deny* outside the window for any change touching `values/common.yaml`, `values/env/*.yaml`, `argo/`, `platform/`, `charts/`. *Allow* anytime for changes scoped to `values/tenants/`.
- [x] 4.2 Write `argo/applicationsets/react-tenants.yaml`. Used multi-source pattern (chart source + values ref source) mirroring Nextcloud-base. Inline `values:` block computes hostname / upstream / TLS secret / commonLabels / branding env vars from `.tenant.environment` switch and `.tenant.branding` map. `goTemplateOptions: ["missingkey=default"]` keeps minimal tenants working.
- [x] 4.3 Verified with `helm template` + `kubeconform`: synthetic tenant `test-mcc-accept` renders 9 resources, all schema-valid. Inline-values logic verified against the ApplicationSet template (smoke-checks.sh reproduces it in bash).

## 5. Platform policies — pod-label-scoped, not namespace-label-scoped

**Approach changed**: rather than standalone YAMLs in `platform/policies/`, NetworkPolicies are templated **in the vendored chart** at `charts/woo-website/templates/networkpolicy.yaml`. They ship per-release and get cleaned up on uninstall. The `platform/policies/` directory carries a README explaining where the policies actually live. Recorded as a divergence from upstream in `charts/woo-website/UPSTREAM`.

- [x] 5.1 default-deny policy templated in chart. Selects pods by `app.kubernetes.io/part-of: react-platform`.
- [x] 5.2 allow-ingress policy: from `networkPolicy.ingressNamespace` (default `ingress-nginx`) to pod port 8080.
- [x] 5.3 allow-egress policy: DNS to `kube-system` + HTTPS (443) to public IPs (RFC1918 ranges blocked to prevent in-cluster lateral movement).
- [ ] 5.4 Verify Nextcloud co-tenant unaffected — deferred to canary cut-over (task 8).

## 6. Scripts

- [x] 6.1 `scripts/validate-values.sh` written. Required fields, env enum, filename convention.
- [x] 6.2 `scripts/smoke-checks.sh` written. Reproduces ApplicationSet inline-values in bash for offline render testing. Verified: 9 resources render clean for synthetic test tenant.
- [ ] 6.3 GitHub Actions workflow — deferred (one cycle of local validation first).

## 7. Docs

- [x] 7.1 `react-platform/docs/ADDING-TENANT.md` written (Dutch). Includes namespace-pairing rule and explicit "DNS/TLS are automatic" callout.
- [x] 7.2 `react-platform/docs/ROLLOUTS.md` written (Dutch). Sync windows, image-bump procedure, wave order, rollback.
- [x] 7.3 `react-platform/docs/MIGRATION.md` written (Dutch). Per-tenant cut-over with concrete `kubectl` commands.

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
