---
last_reviewed: 2026-08-18
owner: info@conduction.nl
---

# Migratie: van losse Applications naar ApplicationSet

Eenmalige cut-over per tenant. Verplaatst de WOO PWA-pod van namespace
`<naam>` naar namespace `<naam>-<environment>` (paired met de Nextcloud
co-tenant). Alleen voor tenants die vandaag draaien onder de oude
`mcc create-react`-flow; nieuwe tenants slaan dit hele proces over.

## Wat verandert er?

| Aspect | Vandaag | Na migratie |
|---|---|---|
| Argo Application-bron | Losstaand manifest in `toolchain/` | ApplicationSet `react-tenants` |
| Application-naam | `<naam>-<env>-reactfront` | `<naam>-<env>-reactfront` (gelijk) |
| Namespace | `<naam>` | `<naam>-<env>` |
| Hostname | Identiek | Identiek |
| Image-tag | `latest` | Pinned semver in `common.yaml` |
| TLS-secret | `woo-pwa-tls` (in oude ns) | `<naam>-<env>-tls` (in nieuwe ns) |
| DNS | external-dns auto | external-dns auto |
| Branding | Inline in losse manifest | `tenant-<naam>.yaml` |

## Voorbereiding (eenmalig)

1. **Snapshot live cluster state** — vereist voor branding-migratie.
   ```bash
   kubectl get applications -n argocd -o yaml \
     | yq '.items[] | select(.metadata.name | test("-reactfront$"))
         | {name: .metadata.name,
            ns_today: .spec.destination.namespace,
            parameters: .spec.source.helm.parameters,
            values: .spec.source.helm.values}' \
     > openspec/changes/bootstrap-react-platform/cluster-state.yaml
   ```
   Dit bestand staat in `.gitignore` — niet commiten.

2. **Per tenant**: voeg een `tenant.frontend:`-blok toe aan het bestaande
   tenant-bestand in **Nextcloud-base**
   (`nextcloud-platform/values/tenants/tenant-<naam>-<env>.yaml`) — zie
   [ADDING-TENANT.md](ADDING-TENANT.md). Kopieer alle `pwa.env.GATSBY_*`
   en `NL_DESIGN_THEME_CLASSNAME` uit `cluster-state.yaml` naar
   `frontend.branding`/`frontend.env`. Tenants zonder branding hebben
   geen blok nodig.

   **BELANGRIJK — image-tag override tijdens cut-over:**
   Zet expliciet in het frontend-blok van elk migrerend tenant-bestand:
   ```yaml
   tenant:
     frontend:
       tag: latest
   ```
   Reden: bestaande tenants draaien `:latest` (digest verschilt van de
   platform-pin `development-V1.0.260422`). Zonder override wisselt
   de tenant tegelijk met de namespace-move ook van image-versie — dubbele
   verandering, dubbel risico. De override zet de tenant gelijk aan zijn
   huidige image. Pas later, in een aparte sync window, verwijder je de
   `tag` om naar de platform-default te tillen — dat is dan een
   bewuste image-upgrade.

3. **Verifieer renders**:
   ```bash
   ./react-platform/scripts/validate-values.sh
   ./react-platform/scripts/smoke-checks.sh
   ```

4. **Nextcloud-namespace check**: voor elke tenant, controleer dat
   `<naam>-<environment>` bestaat als Nextcloud namespace. Als niet:
   blocker — er is geen Nextcloud co-tenant en de pairing-aanname
   geldt niet voor deze tenant.

## Cut-over per tenant

Uitvoeren binnen 17:00–07:00 sync window. Begin met canary
(`test-mcc-accept`).

1. **Pre-state vastleggen**:
   ```bash
   kubectl get all,ingress,cert -n <naam>             > /tmp/pre-old.txt
   kubectl get all,ingress,cert -n <naam>-<env>       > /tmp/pre-new.txt
   ```

2. **Diff render vs live**: vergelijk de `helm template`-output (run
   smoke-checks met dit tenant) met de live Application's resolved
   manifest. Resolve alle inhoudelijke verschillen — alleen
   `metadata.namespace` mag verschillen.

3. **Stop oude Application** (default cascade — verwijdert workload):
   ```bash
   kubectl delete application -n argocd <naam>-<env>-reactfront
   ```
   Wacht tot Deployment, Service, Ingress weg zijn uit `<naam>`. Hostname
   is nu kortdurend onbereikbaar.

4. **Sync ApplicationSet** — Argo maakt de nieuwe Application met dezelfde
   naam, target namespace `<naam>-<env>`. Workload wordt vers gemaakt.

5. **Wacht op TLS**:
   ```bash
   kubectl wait -n <naam>-<env> --for=condition=Ready cert/<naam>-<env>-tls --timeout=5m
   ```
   Als dit timeoutet: oude Ingress blokkeert mogelijk nog de hostname.
   Verifieer met `kubectl get ingress -A | grep <naam>`.

6. **Verifieer bereikbaarheid**:
   ```bash
   curl -I https://<naam>.[accept.]openwoo.app
   openssl s_client -connect <host>:443 -servername <host> < /dev/null \
     | openssl x509 -noout -dates
   ```
   Expect: 200 status, geldige TLS-cert.

7. **Verifieer branding** (alleen voor tenants met overrides):
   ```bash
   curl -s https://<host> | grep -E '<theme-class>|<organisation-name>'
   ```

8. **Verifieer Nextcloud co-tenant onaangetast**:
   ```bash
   kubectl get pods -n <naam>-<env>
   ```
   Restart counts van Nextcloud-pods moeten gelijk zijn aan pre-state.

9. **Soak**: ~24 uur draaien voor de volgende cut-over.

**Totale downtime per tenant**: 1–3 minuten (delete → recreate → TLS-issuance).

## Rollback per tenant

1. Re-apply het oude manifest:
   ```bash
   kubectl apply -f toolchain/woo-application-<naam>-<env>.yaml
   ```
2. Zet `tenant.frontend.enabled: false` in het Nextcloud-base
   tenant-bestand (PR-revert van het frontend-blok kan ook). De
   ApplicationSet stopt met deze tenant te beheren.
3. cert-manager re-issued in de oude namespace zodra de oude Ingress
   weer staat.

## Volgorde

1. Canary: `test-mcc-accept`. Soak 24h.
2. Wave 1: tenants zonder branding (2-regel tenant-bestanden).
3. Wave 2: tenants met branding (Almere, etc.). Extra check op
   theme/org-name na cut-over.
4. Wave 3: edge cases.

Image-tag wordt **niet** gebumpt tijdens de migratie — dat is een
aparte platform-change die na alle cut-overs gepland kan worden.

## Dertien frontends staan buiten GitOps (gemeten 2026-08-18)

Bij de IPv6-uitrol bleven dertien `*-reactfront`-Applications achter. Onderzocht,
en het is geen sync-probleem maar een herkomst-probleem.

| Kenmerk | Deze dertien | Een appset-tenant (bv. `baarn`) |
|---|---|---|
| `ownerReferences` | geen | de ApplicationSet |
| bronvorm | één `spec.source` | `spec.sources` (chart + values) |
| repo | `woo-website-template-apiv2.git`, path `helm/woo-website` | React-base, gevendorde chart |
| `targetRevision` | `main` | vaste revisie |
| tenant-bestand in Nextcloud-base | **geen** (op één na) | ja |

De apps:

    bct-accept        beek-accept       beek-live         ede-accept
    ede-live          koophulpje-live   odmh-accept       soest-accept
    soest-live        stichtsevecht-live  test-accept     vaals-accept
    zandbak-010-live

(suffix `-reactfront`; "live" is de productie-variant)

Van de tien betrokken organisaties heeft er **één** een tenant-bestand
(`stichtsevecht`, en dan alleen accept — juist de live-omgeving hangt hier los).
De andere negen bestaan alleen in het cluster.

### Wat dat betekent

Zonder tenant-bestand kan de ApplicationSet deze Applications niet genereren, dus
missen ze **elke** platformwijziging. Gemeten op drie van hen
(`soest`, `beek`, `zandbak-010`): 0 van de 3 audit-headers
(`Content-Security-Policy`, `X-Frame-Options`, `Referrer-Policy`), geen IPv6, en
de ongetekende Conduction-`security.txt`. Ze draaien op de upstream-chart met
`targetRevision: main`, dus elke commit daar landt ongezien in een
gemeenteomgeving.

Dit is dus breder dan IPv6: het is de restpost van de migratie die
`MIGRATION.md` beschrijft, plus een handvol omgevingen die nooit in de
tenantadministratie zijn opgenomen.

### Voorgestelde volgorde

1. **Vaststellen wat er nog moet leven.** `test-accept`, `zandbak-010-live` en
   `bct-accept` klinken als proef- en zandbakomgevingen. Wat weg kan, moet weg —
   dat is de goedkoopste helft van het probleem.
2. **Per resterende omgeving een tenant-bestand** in Nextcloud-base, dan neemt de
   ApplicationSet hem over bij de volgende sync (zelfde app-naam) en komt hij
   automatisch mee met headers, ECDSA, IPv6 en `security.txt`.
3. **Cutover volgens `MIGRATION.md`**, één tenant per keer, binnen het sync window.
4. `stichtsevecht-live` eerst: daar bestaat het accept-bestand al, dus dat is de
   kleinste stap met de meeste zekerheid.

Niets van dit alles is gedaan; dit is de bevinding, niet de uitvoering.
