## Context

`react-tenants` is a git-files ApplicationSet whose generator reads Nextcloud-base's `nextcloud-platform/values/tenants/tenant-*.yaml` (globs `tenant-canary-*` + `tenant-conduction-*` today). Per-tenant frontend config lives in an optional `tenant.frontend` block in those files; the template already supports `host`, `upstreamHost`, `apiBaseUrl`, `tag`, `branding.*`, and a generic `env` passthrough. TLS is the one knob still hard-coded.

The existing template (lines ~153–165) emits:

```yaml
ingress:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  tls:
    - secretName: "{{ $ncname }}-tls"
      hosts:
        - "{{ $host }}"
```

`global.tls` is deliberately `false` so the chart does not mint its own second cert; the appset supplies `ingress.tls` directly.

### External dependencies (already in place — not in scope)

- cert-manager + `letsencrypt-prod` ClusterIssuer (cluster-infra)
- external-dns auto-manages DNS records from Ingress hostnames (zones `commonground.nu` / `openwoo.app` / `opencatalogi.nl`)

## Goals / Non-Goals

**Goals**
- A per-tenant TLS override that covers all three observed cert patterns without breaking the default.
- A migration runbook that preserves the live certificate per tenant and never depends on bulk re-issuance.

**Non-Goals**
- Solving renewal of bring-your-own certs (follow-up).
- Migrating more than one tenant per cutover.
- Any change to the generator glob (widening to more tenants is a separate, later change per `react-platform/docs/MIGRATION.md`).

## Decisions

### Decision 1: TLS contract is `tenant.frontend.tls`, written in Nextcloud-base

Keep the single-source-of-truth invariant ("Argo ís de watcher"): the field is written in the Nextcloud-base tenant file and *consumed* by this appset. Shape:

```yaml
tenant:
  frontend:
    host: open.oude-ijsselstreek.nl      # already supported
    tls:
      secretName: oudeijsselstreek-prod-tls   # optional; default <ncname>-tls
      issuer: none                            # optional; default letsencrypt-prod; "none" omits the annotation
```

Three resulting modes:
1. **Default (omit `tls`)** → `secretName=<ncname>-tls`, `cert-manager.io/cluster-issuer: letsencrypt-prod`. Identical to today.
2. **LE on a custom/pre-seeded secret** → set `secretName`; issuer stays `letsencrypt-prod`. Lets us point at a copied LE secret so cert-manager adopts it instead of re-issuing.
3. **Bring-your-own / pre-seeded cert** → set `secretName` + `issuer: none`. The Ingress references the secret; no cert-manager annotation, so cert-manager stays out and the customer cert is served as-is.

### Decision 2: Implement as conditional template logic, not a chart change

`ingress.annotations` and `ingress.tls` already pass through the vendored chart to the rendered Ingress. So the change is localised to the appset template:

```yaml
{{- $tls := default (dict) (index $fe "tls") -}}
{{- $tlsSecret := default (printf "%s-tls" $ncname) (index $tls "secretName") -}}
{{- $issuer := default "letsencrypt-prod" (index $tls "issuer") -}}
ingress:
  annotations:
    {{- if ne $issuer "none" }}
    cert-manager.io/cluster-issuer: {{ $issuer }}
    {{- end }}
  tls:
    - secretName: "{{ $tlsSecret }}"
      hosts:
        - "{{ $host }}"
```

Task 1 verifies the passthrough assumption before relying on it; if the chart drops these keys, wire them there too.

### Decision 3: Preserve the cert by seeding the secret into the new namespace

The legacy cert lives in the old bare-org namespace; the new frontend lands in `<ncname>`. Rather than re-issue, the runbook copies the live cert secret into `<ncname>` under the name the appset will reference, *before* cutover:
- For LE-managed tenants where the domain still validates: copying lets cert-manager adopt the valid cert and skip issuance until near expiry (mode 2).
- For BYO / non-cert-manager tenants: copying is mandatory and paired with `issuer: none` (mode 3) so cert-manager does not clobber it.

This makes every cutover cert-neutral and keeps us under the LE rate limit.

## Risks / Trade-offs

- **LE rate limit on `openwoo.app`** (50 certs/registered-domain/week). Mitigation: prefer secret-seeding over re-issue; cap fresh `openwoo.app` issuances per week; custom domains are separate buckets.
- **BYO cert renewal gap.** A copied hand-managed cert in `<ncname>` will not auto-renew. Mitigation: the runbook records expiry + renewal owner per BYO tenant and flags a follow-up to move it onto cert-manager where the customer permits.
- **Per-cutover downtime** (1–3 min) while the legacy Application is deleted and the appset recreates in `<ncname>`. Accepted; done in the sync window, one tenant at a time.
- **Secret duplication during transition.** The cert briefly exists in both namespaces. Cleaned up when the legacy namespace is reaped post-verification.

## Migration Plan (per tenant, repeated 1×N)

1. **Cert audit.** Classify the tenant: ingress-shim LE / `Certificate`-CR LE / hand-applied BYO. Record domain(s), current secret name + namespace, and whether cert-manager-managed + expiry.
2. **Seed the cert** into `<ncname>` under the target secret name.
3. **Write the `frontend:` block** in the Nextcloud-base tenant file: `host`, `tag` (current live image tag — migrate-at-current-tag), `branding`, `env`, and `tls` (secretName + issuer mode per the audit).
4. **Land the tenant-file change** (PR — tenant files are allowed any time, but the cutover step below is sync-window-bound).
5. **Cutover** (in window): delete the legacy `<org>-<env>-reactfront` Application + its workload in the old namespace; the appset creates the new one in `<ncname>`.
6. **Verify**: TLS chain valid for the customer host, page loads, branding correct, upstream reachable.
7. **Cleanup**: remove orphaned legacy secret/namespace remnants once verified.
8. **Rate-limit gate**: before the next tenant, confirm weekly `openwoo.app` issuance budget remains.

## Open Questions

- Per-tenant or batched-by-week sequencing within the window? (Default: a small number per window, canary-class tenant first.)
- For BYO certs: move to cert-manager DNS-01 now (needs customer DNS delegation) or defer to the renewal follow-up?
- Do any customer domains require their cert to *stay* outside cert-manager for compliance reasons? Capture during the audit.
