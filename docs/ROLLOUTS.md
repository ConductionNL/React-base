---
last_reviewed: 2026-07-06
owner: info@conduction.nl
---

# Rollouts

## Sync windows

Argo CD AppProject `react-platform` blokkeert platform-syncs tijdens
kantooruren. Schema (Europe/Amsterdam, automatisch CET/CEST):

| Periode | Mag synced worden |
|---|---|
| Ma–Vr 07:00–17:00 | **Nee** (alleen platform `react-platform` Application) |
| Ma–Vr 17:00–07:00 | Ja |
| Weekend | Technisch ja, **operationeel: alleen na expliciete OK** |

Operationele regel (uit `CLAUDE.md`): platform-wijzigingen alleen
**Ma–Do 17:00–07:00**. Vrijdagavond en weekenden alleen met goedkeuring
van mwest2020. Sociaal afgedwongen, niet technisch — de AppProject
blokkeert weekends niet zelf.

Tenant-specifieke wijzigingen (het tenant-bestand of `tenant.frontend:`-blok
in **Nextcloud-base** `values/tenants/`) zijn altijd toegestaan: ze raken
één Application, niet de hele platform-meta.

## Wat telt als platform-wijziging?

- `values/common.yaml` — image-tag, security defaults, nodepool, ingress class
- `values/env/*.yaml` — replicas, HPA, resources per omgeving
- `argo/` — AppProject, ApplicationSet
- `charts/` — vendored chart bumps
- `react-platform/platform/` — netwerk policies (in chart) of platform-componenten

## Wat is een tenant-wijziging?

Alles in het tenant-bestand in **Nextcloud-base**
(`nextcloud-platform/values/tenants/tenant-*.yaml`):

- Nieuwe tenant toevoegen (frontend volgt automatisch)
- `tenant.frontend:`-blok toevoegen of aanpassen (branding, tag, host)
- Tenant of frontend verwijderen (`enabled: false`)

## Image-tag bumpen

Image-tags zijn pinned in `values/common.yaml`. Een bump werkt door op
**alle** tenants in **alle** omgevingen tegelijkertijd via Argo's auto-sync.

Procedure:
1. Update `pwa.image.tag` in `values/common.yaml` (PR).
2. Wacht op een 17:00 sync window.
3. Argo synct alle Applications. Wave 0 (canary) eerst, dan wave 1+.
4. Verifieer canary werkt voordat wave 1 doorrolt.

Rolling update: chart-default is RollingUpdate (geen `strategy: Recreate`
zoals in de oude losse manifests — die directive werd door de chart
genegeerd, geen functional change). Kortdurend overlap van oude + nieuwe
pod tijdens elke tenant-update.

## Per-tenant image-pin: wie wint, git of de Argo UI?

Een tenant kan de platform-default overrulen met `tenant.frontend.registry`,
`tenant.frontend.repository` en `tenant.frontend.tag` in zijn tenant-bestand
in Nextcloud-base. Elk deel heeft zijn eigen veld; de ApplicationSet stelt er
`<registry>/<repository>:<tag>` van samen.

De eigenaarsregel hangt af van of de tenant pint:

| Tenant-bestand | Image | Branding (`GATSBY_*`) |
|---|---|---|
| geen pin, geen `branding`-blok | live bijstellen in Argo blijft staan | live bijstellen blijft staan |
| pint `registry`/`repository`/`tag` | **git wint**, Argo reconcilieert | ongewijzigd |
| heeft een `branding`-blok | ongewijzigd | **git wint**, Argo reconcilieert |

De ApplicationSet emit `ignoreDifferences` daarom per tenant verschillend, via
`spec.templatePatch` in `react-platform/argo/applicationsets/react-tenants.yaml`.

Let op bij het toevoegen van een pin of een `branding`-blok aan een tenant die
tot dan toe live werd bijgesteld: vanaf dat moment overschrijft git de live
waarde. Controleer dus eerst wat er live draait (`kubectl -n <tenant> get deploy
woo-website -o jsonpath='{.spec.template.spec.containers[0].image}'`) en zet die
waarde in git, tenzij je bewust wilt wisselen.

Achtergrond: tot 2026-08-11 was de image altijd ignore-diffed. Een tag die
keurig in git stond landde daardoor nooit op een bestaande Deployment — Argo
bleef Synced terwijl live iets anders draaide (epe-accept, 2026-08-11).

## Wave-volgorde

Tenants kunnen `tenant.wave` zetten (default `"1"`). De ApplicationSet
zet `argocd.argoproj.io/sync-wave: "<wave>"` als annotation, Argo
respecteert dat tijdens sync.

| Wave | Bedoeld voor |
|---|---|
| 0 | Canary tenant — kleine groep, valideren vóór de rest |
| 1 | Standaard tenants |
| 2+ | Late waves (specifiek branding, edge cases) |

## Rollback

Plat: revert de PR + sync.

Image-tag rollback:
1. Revert de `values/common.yaml` commit.
2. Argo detecteert drift en sync't terug naar de vorige tag (mits binnen
   sync window — anders manueel sync via Argo UI met operator-rol).

Tenant-config rollback:
1. Revert tenant-bestand.
2. Direct sync (tenant changes hebben geen window-restrictie).

## Soak-eis

Na een platform-bump (image of chart): minimaal **24 uur** soaken op
canary (wave 0) voordat wave 1+ wordt vrijgegeven. Geen automatische
gate; operator-discipline.
