---
last_reviewed: 2026-08-10
owner: info@conduction.nl
---

# Tenant toevoegen

**In deze repo maak je géén tenant aan.** De bron van waarheid is
`Nextcloud-base/nextcloud-platform/values/tenants/` — de ApplicationSet
`react-tenants` watcht die directory rechtstreeks ("Argo ís de watcher").
Een Nextcloud-tenant toevoegen betekent automatisch een WOO PWA-frontend
erbij: de frontend-vloot is een pure functie van de Nextcloud-tenantvloot,
zonder tweede bestand en dus zonder drift.

## Stappen

1. Voeg de tenant toe in **Nextcloud-base** (zie `ADDING-TENANT.md` in
   die repo): één `tenant-<naam>-<env>.yaml` met minimaal `tenant.name`
   en `tenant.environment`.
2. (Optioneel) Configureer de frontend via een `tenant.frontend:`-blok
   in **datzelfde** bestand — zie hieronder. Geen blok = frontend met
   platform-defaults (opt-out-model).
3. Valideer vanuit deze repo (vereist een Nextcloud-base checkout):
   ```bash
   ./react-platform/scripts/validate-values.sh
   ./react-platform/scripts/smoke-checks.sh
   ```
4. Na merge in Nextcloud-base maakt Argo CD de Application
   `<tenant.name>-reactfront` aan. Hostname (`<org>.openwoo.app` of
   `<org>.accept.openwoo.app`), DNS (external-dns), TLS (cert-manager)
   en NetworkPolicies volgen automatisch.

## Het `tenant.frontend:`-blok

```yaml
tenant:
  name: almere-accept        # encodeert al de omgeving
  environment: accept
  frontend:
    enabled: true            # false = geen frontend (interne/test-tenants)
    tag: "development-V1.0.260422"   # per-tenant image-pin
    host: "woo.almere.nl"    # override van <org>.openwoo.app
    branding:
      organisationName: "Gemeente Almere"
      themeClassname: almere-theme
      jumbotronImageUrl: "https://..."
      faviconUrl: "data:image/png;base64,..."
      footerHideLogo: true
    env:                     # vrije GATSBY_*/NL_DESIGN_* passthrough
      GATSBY_SOMETHING: "x"
```

Al het overige (hostname, upstream-API-URL, TLS-secret, namespace) leidt
de ApplicationSet af uit `tenant.name` + `tenant.environment` — zie
`react-platform/argo/applicationsets/react-tenants.yaml`.

## Frontend uitzetten of tenant verwijderen

**Lees eerst wat `preserveResourcesOnDeletion: true` wél en niet doet.** De vlag
bewaart de **resources**, niet de Application. Zodra een tenant uit de generator
valt — het bestand weg, of de post-selector die hem eruit filtert — verwijdert
de appset-controller de Application `<tenant.name>-reactfront`. Deployment,
Service en Ingress blijven staan. Zonder Application is er ook geen `selfHeal`
meer die ze bijstuurt: de frontend draait door, **serveert verkeer op zijn
publieke host** en wordt door niets meer beheerd. Opruimen is altijd een
handmatige stap.

- **Alleen de frontend uit**: `tenant.frontend.enabled: false` in het
  Nextcloud-base tenant-bestand haalt de tenant uit de post-selector
  (`matchExpressions: tenant.frontend.enabled NotIn ["false"]`). De Application
  verdwijnt — **maar de frontend blijft online**. "Uit" is het pas ná de
  opruimstap hieronder. Ruim dus altijd op, anders staat er een frontend die
  niemand meer bijwerkt.

- **Hele tenant weg**: verwijder het tenant-bestand in Nextcloud-base. De
  canonieke procedure staat in **`Nextcloud-base/docs/REMOVING-TENANT.md`**
  (inclusief backup en de verplichte stap om de host uit de probe-lijsten te
  halen). Dezelfde opruimstap geldt.

### Opruimen

Aanbevolen: `openwoo-app-config/scripts/cleanup-tenant.sh --tenant <tenant.name>`
— zonder `--execute` toont het alleen een plan en verandert het niets. Het ruimt
beide Applications (`nc-<tenant>` en `<tenant>-reactfront`) en de namespace op.

Alleen de frontend, met de namespace intact:

```bash
TENANT=<tenant.name>

kubectl delete application -n argocd "$TENANT-reactfront"
kubectl delete -n "$TENANT" all,ingress,networkpolicy \
  -l react.platform/tenant="$TENANT"
```

Let op het label: `react.platform/tenant` draagt de **volledige `tenant.name`**
(bijv. `almere-accept`), niet de kale organisatie — zie `commonLabels` in de
ApplicationSet. Een selector op `<org>` matcht niets en laat de frontend staan.

external-dns ruimt het Cloudflare-record op zodra de Ingress weg is.
