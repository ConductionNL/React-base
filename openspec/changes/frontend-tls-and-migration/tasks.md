## 1. Verify assumptions — no cluster mutation

- [ ] 1.1 Confirm the vendored `charts/woo-website` passes `ingress.annotations` and `ingress.tls` through to the rendered Ingress (helm template a tenant with a custom secret + `issuer: none` and inspect output). If either key is dropped, note the chart fix needed.
- [ ] 1.2 Re-run the fleet cert scan and freeze it as ground truth in this change dir:
  ```bash
  kubectl get ingress -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"\t"}{range .spec.rules[*]}{.host}{","}{end}{"\tsecret="}{range .spec.tls[*]}{.secretName}{","}{end}{"\tissuer="}{.metadata.annotations.cert-manager\.io/cluster-issuer}{"\n"}{end}' \
    | grep -iE 'woo-website|reactfront|react-woo' | sort > openspec/changes/frontend-tls-and-migration/cert-state.tsv
  ```
- [ ] 1.3 For every ingress with an empty issuer, classify it: standalone `Certificate` CR (LE) vs hand-applied/customer cert (check `kubectl get certificate -n <ns>` and the secret's `cert-manager.io/issuer-name` annotation). Record the verdict per tenant.

## 2. Template change — render-only, no deploy

- [ ] 2.1 Add the derived TLS block to `react-platform/argo/applicationsets/react-tenants.yaml` (Decision 2): `$tls` / `$tlsSecret` / `$issuer`, conditional cluster-issuer annotation, overridable `secretName`.
- [ ] 2.2 Prove backward-compat: render `canary-accept`, `canary-prod`, `conduction-test`, `conduction-straattest-accept` with the new template and diff against the current render — must be byte-identical (no `tls` block on those tenants).
- [ ] 2.3 Render the three modes from a scratch tenant fixture (default / custom-secret+LE / custom-secret+`issuer: none`) and confirm the Ingress annotation appears/disappears and the secretName flips as designed.

## 3. Contract documentation

- [ ] 3.1 Document `tenant.frontend.tls.{secretName,issuer}` in `react-platform/docs/` (and cross-reference from the Nextcloud-base tenant docs, since the field is written there).
- [ ] 3.2 Write the per-tenant migration runbook in `react-platform/docs/MIGRATION.md` from design.md "Migration Plan", including the cert-seed commands and the LE rate-limit gate.

## 4. Dry-run on one tenant (in sync window) — pick a low-risk first

- [ ] 4.1 Choose the first migration target. Proposal: a `*.openwoo.app` accept tenant with no BYO cert (cleanest), NOT a customer-domain prod tenant. Confirm with operator.
- [ ] 4.2 Execute the runbook end-to-end for that one tenant; record actual downtime and whether the cert was preserved (no new LE order) or re-issued.
- [ ] 4.3 Cleanup the legacy app/namespace; verify the live page, TLS chain, branding, and upstream.
- [ ] 4.4 Retro: confirm the runbook steps and timings before promoting to the next tenant. Do NOT batch.

## 5. Done criteria

- [ ] 5.1 New + existing tenants render correctly across all three TLS modes; default path unchanged.
- [ ] 5.2 One real tenant migrated cert-neutrally, verified, legacy cleaned up.
- [ ] 5.3 `CHANGELOG.md` updated (react-base). Runbook merged. Remaining tenants enumerated with their audited cert mode for sequential migration.
