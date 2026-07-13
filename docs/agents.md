---
last_reviewed: 2026-07-08
owner: info@conduction.nl
---

# Agent-cataloog (referentie)

Guardrails voor agents in deze repo, per het handboek-formaat
(org → Werken met agents). **Niet in dit cataloog = eerst vragen.**

Kernfeit: deze repo bezit géén tenant-bestanden — tenants (en hun
frontend-blok) leven in Nextcloud-base ("Argo ís de watcher").

## Operaties

| Operatie | Autonomie | Idempotentie | Verificatie |
|---|---|---|---|
| Frontend-blok voor een tenant wijzigen | autonoom — maar in **Nextcloud-base** (volg het cataloog dáár) | declaratief | verify in beide repos |
| Chart-/template-wijzigingen (vendored chart, ApplicationSet-template) | autonoom bewerken | declaratief | `./scripts/verify.sh` (vloot-render + kubeconform); dit is een platform-wijziging: mens beslist over push binnen sync window |
| `values/common.yaml` / `values/env/*` wijzigen (image-tag, resources) | mens-vereist | — | raakt álle tenants; ROLLOUTS.md-flow, sync windows, canary eerst |
| Legacy-migratie cut-over per tenant | mens-vereist | — | MIGRATION.md-runbook; agent bereidt bestanden en checks voor |
| Docs bijwerken | autonoom | tekstueel | docs-contract-gate |
| Elke `kubectl`/Argo-mutatie; push | mens-vereist | — | agent levert commando + rollback |
| Tenant-bestanden aanmaken in déze repo | verboden | — | de bron is Nextcloud-base; de doc-assertion in verify bewaakt dit |

## Grondwaarheid en gedrag

- Handboek (MCP `conduction-docs`) boven modelkennis; ADDING-TENANT.md
  hier beschrijft de echte flow.
- GET-check-first; sync windows (ma–do 17:00–07:00 voor platform-werk)
  zijn mensenwerk — de agent plant er niet zelf omheen.
