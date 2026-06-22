## Why

The `bootstrap-react-platform` change put per-tenant TLS **out of scope** ("cert-manager + HTTP-01, already wired in cluster-infra. No per-tenant cert configuration in this repo"). That was correct for the canary/conduction tenants, which all live on `*.openwoo.app` and get a fresh Let's Encrypt cert via the ApplicationSet's hard-coded ingress annotation:

```yaml
ingress:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod   # hard-coded
  tls:
    - secretName: "{{ $ncname }}-tls"                   # derived, no override
```

But the 44 legacy `*-reactfront` apps we still need to migrate do **not** fit that single mode. A cluster scan (2026-06-22) of every `woo-website`/`reactfront` ingress shows three distinct cert patterns:

| Pattern | Examples | Cert source |
|---|---|---|
| Platform domain `*.openwoo.app` | almere, baarn, soest, helmond, odmh | LE via ingress-shim annotation |
| Own customer domain `open.<gemeente>.nl` + ingress-shim | dinkelland, lansingerland, moerdijk, zutphen, tubbergen | LE via ingress annotation |
| Own customer domain, **no** ingress issuer | oudeijsselstreek, roosendaal, noorderzijlvest, hofvantwente-accept, buren-prod | LE via standalone `Certificate` CR **or** a hand-applied / customer-supplied cert |

Two facts make naive migration unsafe:

1. **Namespace move.** Legacy frontends live in the bare-org namespace (`oudeijsselstreek`); the ApplicationSet lands the new frontend in the Nextcloud namespace `<ncname>` (`oudeijsselstreek-prod`). The existing cert secret is in the *old* namespace and cannot be referenced across namespaces — so every naive cutover re-issues.
2. **Re-issue blast radius.** ~Half the fleet shares the single registered domain `openwoo.app`. Migrating many at once triggers fresh LE issuance per tenant and risks the Let's Encrypt **50 certs / registered domain / week** limit. And for the bring-your-own-cert tenants, the hard-coded `letsencrypt-prod` annotation would either fail validation on a customer domain or overwrite a manually-managed cert.

So the new world needs a per-tenant TLS escape hatch, plus a careful, **one-at-a-time** migration runbook with a per-tenant cert audit and legacy cleanup.

## What Changes

- **`react-tenants` ApplicationSet template** (`react-platform/argo/applicationsets/react-tenants.yaml`): replace the two hard-coded TLS lines with a derived block driven by an optional `tenant.frontend.tls` object read from the Nextcloud-base tenant file:
  - `secretName` — overrides the derived `<ncname>-tls`
  - `issuer` — overrides `letsencrypt-prod`; the literal `none` **omits** the `cert-manager.io/cluster-issuer` annotation entirely (bring-your-own / pre-seeded cert)
  - Default behaviour (block absent) is byte-for-byte unchanged → backward compatible with canary/conduction.
- **Chart passthrough check** (`charts/woo-website`): confirm `ingress.annotations` and `ingress.tls` already flow through to the rendered Ingress (they do today via the appset). No chart change expected; if a gap is found, wire it.
- **`react-platform/docs/MIGRATION.md`**: add the cert-aware, per-tenant migration runbook (audit → relocate cert → set `frontend:` block → cutover → verify → cleanup), with the LE rate-limit guard.
- **Nextcloud-base tenant contract docs**: document the `tenant.frontend.tls` keys alongside the existing `host` / `tag` / `branding` / `env`. (The fields are *consumed* by react-base but *written* in Nextcloud-base tenant files — "Argo ís de watcher".)

## Capabilities

### New Capabilities

- `frontend-tls-override`: a tenant may pin a custom TLS secret name and disable the cert-manager issuer, so customer-provided certs and pre-seeded secrets are honoured instead of always minting `<ncname>-tls` via LE.
- `cert-safe-migration`: a documented, repeatable, one-tenant-at-a-time cutover that preserves the existing certificate (copy/seed into the new namespace) and never relies on bulk re-issuance.

### Out of Scope

- `byo-cert-renewal`: this change lets us *reference* a bring-your-own cert, but does not solve its **renewal** (a hand-applied cert in the new namespace will not auto-renew). Establishing a renewal path (move to cert-manager DNS-01, or a tracked manual renewal) is a follow-up, flagged per affected tenant in the runbook.
- `bulk-migration`: explicitly rejected. Migration is strictly one tenant per cutover, with verification and legacy cleanup between each.
- `deploy`: this change ships template + docs only. Executing migrations happens later, inside the AppProject sync window (Mon–Thu 17:00–07:00 Europe/Amsterdam).

## Impact

- **`react-tenants` ApplicationSet**: template-only change; the generator glob and per-tenant Application identity are untouched. Existing live frontends (canary, conduction-*) re-render identically (default TLS path unchanged).
- **Nextcloud-base tenant files**: gain optional `tenant.frontend.tls` keys. No change to any existing tenant unless an operator adds the block during that tenant's migration.
- **Cutover per tenant**: deletes the legacy `<org>-<env>-reactfront` Application in the old bare-org namespace; the ApplicationSet recreates it in `<ncname>`. 1–3 min downtime per tenant, inside the sync window. Legacy namespace remnants and orphaned secrets cleaned up after verification (the appset sets `preserveResourcesOnDeletion: true`, so cleanup is deliberate/manual).
- **Let's Encrypt**: the runbook caps fresh `openwoo.app` issuances per week to stay under the 50/registered-domain limit; custom-domain tenants are separate registered domains and not constrained by that bucket.
