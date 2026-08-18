---
last_reviewed: 2026-08-18
owner: info@conduction.nl
---

# react-base

Documentatie voor het react-platform: WOO PWA-tenants als GitOps
(ApplicationSet `react-tenants`, co-tenancy met Nextcloud-base
namespaces, DNS/TLS automatisch via cluster-infra).

- [Tenant toevoegen](ADDING-TENANT.md) — nieuwe WOO PWA-tenant in twee
  minuten, plus validatie en verwijderen (how-to).
- [Bootstrap](BOOTSTRAP.md) — eenmalige setup om Argo CD deze repo te
  laten zien (how-to). Volgt hetzelfde kubectl-patroon als de
  Nextcloud-base bootstrap.
- [Migratie](MIGRATION.md) — eenmalige cut-over per tenant van de oude
  `mcc create-react`-flow naar de ApplicationSet (how-to).
- [Rollouts](ROLLOUTS.md) — sync windows, platform- vs
  tenant-wijzigingen, image-bumps, waves, rollback (referentie).
- [Security-headers en certificaatsleutel](SECURITY-HEADERS.md) — de
  audit-set (CSP, X-Frame-Options, Referrer-Policy), waarom CSP op
  Report-Only staat, en de ECDSA-sleutel bij een eigen certificaat
  (referentie).
- [Gateway API-route](GATEWAY-API.md) — een frontend-tenant naast zijn
  Ingress op de gedeelde Gateway zetten, en waarom de cutover het
  weghalen van de Ingress is (how-to).

De Nextcloud-kant van een tenant (de co-tenant namespace) is
gedocumenteerd in `Nextcloud-base`.
