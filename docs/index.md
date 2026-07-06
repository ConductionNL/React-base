---
last_reviewed: 2026-07-06
owner: mark
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

De Nextcloud-kant van een tenant (de co-tenant namespace) is
gedocumenteerd in `Nextcloud-base`.
