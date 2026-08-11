---
last_reviewed: 2026-07-06
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
    registry: "docker.io"    # optioneel; alleen samen met repository
    repository: "conduction2022/woo-website-v2"   # optioneel, zonder host en zonder tag
    tag: "V1.0.260422-development"                # alleen het tag-deel
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

### Image-velden

De image-reference bestaat uit drie losse velden; de ApplicationSet stelt er
`<registry>/<repository>:<tag>` van samen. Laat je ze weg, dan geldt de
platform-default uit `react-platform/values/common.yaml`.

| Veld | Inhoud | Voorbeeld |
|---|---|---|
| `registry` | alleen de host, optioneel met poort | `docker.io`, `ghcr.io` |
| `repository` | het pad, zonder host en zonder tag | `conduction2022/woo-website-v2` |
| `tag` | alleen het tag-deel | `V1.0.260422-development` |

Stop géén volledige reference in `tag`: `tag: "woo-website-v2:V1.0.260422-development"`
rendert als `…/woo-website-v2:woo-website-v2:V1.0.260422-development` en is
ongeldig. Nextcloud-base's `nextcloud-platform/scripts/validate-values.sh`
weigert die vorm in CI. `registry` zonder `repository` is eveneens een fout —
de ApplicationSet zou hem stil negeren.

Pin je een van deze velden, dan wint git en reconcilieert Argo de image; pin je
niets, dan blijft de image live bijstelbaar in de Argo UI. Hetzelfde geldt voor
`branding` versus de `GATSBY_*`-env. Zie [ROLLOUTS.md](ROLLOUTS.md) §
"Per-tenant image-pin: wie wint, git of de Argo UI?".

## Frontend uitzetten of tenant verwijderen

- **Alleen de frontend uit**: zet `tenant.frontend.enabled: false` in het
  Nextcloud-base tenant-bestand.
- **Hele tenant weg**: verwijder het tenant-bestand in Nextcloud-base
  (volg `REMOVING-TENANT.md` daar). Let op:
  `preserveResourcesOnDeletion: true` — de frontend-Application en
  resources blijven staan tot een operator ze bewust opruimt:
  ```bash
  kubectl delete application -n argocd <tenant.name>-reactfront
  kubectl delete -n <tenant.name> -l react.platform/tenant=<org> all,ingress,networkpolicy,cert
  ```
  external-dns ruimt het Cloudflare-record op zodra de Ingress weg is.
