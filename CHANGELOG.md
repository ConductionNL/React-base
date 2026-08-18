# Changelog

All notable changes to this repository are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Toegevoegd — 2026-08-18 (IPv6 via de Cloudflare-proxy, per tenant aan te zetten)
- Nieuw veld `tenant.frontend.proxied`. Staat het op `true`, dan emit de
  ApplicationSet `external-dns.alpha.kubernetes.io/cloudflare-proxied: "true"` op
  de Ingress en zet external-dns het DNS-record achter de proxy. Dat levert AAAA
  op zonder dat onze loadbalancer IPv6 hoeft te doen.
- **Niet in `values/common.yaml`,** hoe verleidelijk ook. Alle 92 frontend-apps
  staan op auto-sync met selfHeal; een platform-default zou de hele vloot binnen
  minuten proxyen. Vandaag gemeten: 72 van 92 apps waren drie minuten na een push
  al op de nieuwe revisie. Canary eerst betekent dus per tenant, niet per default.
- Aangezet op de **live-canary**, niet op de accept-canary. Universal SSL van
  Cloudflare dekt `openwoo.app` en `*.openwoo.app`, maar geen tweede niveau zoals
  `*.accept.openwoo.app`; een geproxiede accept-host geeft daardoor een
  TLS-handshakefout. Gemeten op `canary.accept.openwoo.app`, dat al geproxied
  stond. Voor dat niveau is Advanced Certificate Manager nodig (betaalde add-on).
- Bestaande tenants renderen byte-identiek:
  van de 22 goldens veranderde er geen, er kwamen alleen twee nieuwe bij voor de
  testcase `proxied`.
- Voorwaarde aan de Cloudflare-kant: een Configuration Rule met SSL Full (strict)
  voor de geproxiede host. De zone staat op Flexible en kan niet zone-breed om —
  zie `cluster-infra/docs/cloudflare-ipv6.md`.
- Veilig voor `*.openwoo.app` omdat dat wildcard via `letsencrypt-dns` (DNS-01)
  vernieuwt; er loopt geen HTTP-challenge door de proxy.


### Toegevoegd — 2026-08-18 (security-response-headers en ECDSA-certificaatsleutel)
- Aanleiding: audit op `open.dinkelland.nl`. Gemeten op 2026-08-18 ontbraken
  `Content-Security-Policy`, `X-Frame-Options` en `Referrer-Policy`; HSTS en
  `X-Content-Type-Options` werden al geserveerd. Het certificaat was
  Let's Encrypt **RSA-2048**, in de audit als phase-out aangemerkt.
- Nieuw `securityHeaders`-blok in `charts/woo-website/values.yaml`, gerenderd op
  **twee** datapaden: een `configuration-snippet`-annotatie op de Ingress
  (`more_set_headers`) en een `ResponseHeaderModifier`-filter op de HTTPRoute.
  Eén bron, zodat een tenant tijdens de Gateway-migratie via beide paden
  dezelfde headers krijgt. Beide mechanismen *vervangen* een header en zetten er
  geen tweede bij, dus wat de pod al stuurt blijft enkelvoudig.
- CSP staat bewust op **Report-Only**. Gemeten in de live bundel: één inline
  `<script>` (Gatsby-loader, hash wisselt per build), 39 inline
  `style=`-attributen, fonts van `fonts.gstatic.com` en `db.onlinewebfonts.com`,
  branding-afbeeldingen van een externe host per tenant. Enforce pas na meten
  per tenant, anders breekt de site.
- `custom-headers` (de niet-snippet-annotatie van ingress-nginx 1.12) is
  bekeken en afgevallen: die eist eerst `global-allowed-response-headers` in de
  globale controller-ConfigMap, en die staat niet in Git.
- ApplicationSet `react-tenants`: naast `cert-manager.io/cluster-issuer` nu ook
  `private-key-algorithm: ECDSA` + `private-key-size: "256"` voor
  custom-domain-tenants. Raakt alleen tenants met een eigen certificaat; het
  gedeelde openwoo-wildcard staat buiten deze repo. **Let op:** dit wijzigt de
  Certificate-spec, dus cert-manager geeft per geraakte tenant éénmalig een nieuw
  certificaat uit — inplannen binnen het sync window.
- Golden `issuer-cert-manager.values.yaml` bijgewerkt; `./scripts/verify.sh`
  groen (20/20 render-tests).
- Niet in deze wijziging, wel gemeten en gemeld: TLS 1.2 accepteert nog
  `rsa_pkcs1_sha224` (zit in de nginx-controller, niet in Git), de geserveerde
  `security.txt` is ongetekend en zit in het image, en de bundel haalt fonts bij
  Google (`fonts.gstatic.com`).

### Toegevoegd — 2026-08-18 (ondertekende security.txt en publieke sleutel per tenant)
- Nieuw `wellKnown.files` in de chart-values plus `templates/wellknown.yaml`: een
  ConfigMap met bestanden die met `subPath` over `/usr/share/nginx/html/.well-known/`
  worden gemount. Zonder het blok rendert er niets extra's.
- `templates/deployment.yaml` krijgt de mounts en een `checksum/wellknown`-annotatie
  op de pod: een `subPath`-mount ververst niet vanzelf als de ConfigMap wijzigt.
- ApplicationSet geeft `tenant.frontend.wellKnown` door. De inhoud is
  PGP-ondertekend, dus byte-exactheid is een eis en geen wens; het renderharnas
  kreeg daarvoor `indent`/`nindent` (spiegelt sprig: ook lege regels krijgen de
  padding, wat een YAML-blokscalar precies nodig heeft).
- **Bewezen, niet aangenomen:** tenant-bestand → ApplicationSet → chart →
  ConfigMap levert byte-identieke inhoud op, en `gpg --verify` op de gerenderde
  `security.txt` geeft *Good signature from "security@noaberkracht.nl"*. Nieuwe
  testcase `wellknown` (22/22 render-tests groen).
- Aanleiding: de live `security.txt` was de ongetekende Conduction-template, en
  `/.well-known/pgp-key.txt` viel in de SPA-catch-all — status 200 met 5 MB HTML
  in plaats van een sleutel (gemeten 2026-08-18 op open.dinkelland.nl).
- `docs/ADDING-TENANT.md`: secties over `frontend.wellKnown` en over de
  ECDSA-annotaties bij de issuer-tak.
- Nieuwe pagina `docs/SECURITY-HEADERS.md` (in `docs/index.md` opgenomen): de
  headerset, waarom CSP op Report-Only staat en hoe je per tenant naar enforce
  toe werkt, plus wat níét uit deze repo komt (HSTS, nosniff, SHA-224, CAA/DNS).

### Toegevoegd — 2026-08-17 (Gateway API-route per tenant, uit tenzij aangezet)
- Nieuw `charts/woo-website/templates/httproute.yaml` plus een `gatewayRoute`-blok
  in de chart-values. Rendert een `HTTPRoute` naast de bestaande Ingress voor de
  migratie weg van ingress-nginx (upstream gearchiveerd, geen CVE-patches meer).
- Opt-in via `gateway.frontend: true` in het tenant-bestand — dat staat in
  Nextcloud-base. Custom-domain tenants zetten er `gateway.sectionName` bij,
  want die vallen niet onder het openwoo-wildcard.
- **Bestaande tenants renderen byte-identiek.** De ApplicationSet emit het blok
  alleen als de vlag er staat, ook geen `enabled: false`: een blok dat altijd
  meegaat zou alle 84 Applications tegelijk laten hersyncen. Bewezen door de
  golden-tests — 20 van 20 groen zonder wijziging aan een bestaande golden.
- Twee nieuwe testcases (`gateway-route`, `gateway-route-sectionname`). De
  eerste versie van de template plakte `gatewayRoute:` aan de vorige regel door
  verkeerde template-chomping; de suite ving dat vóór het cluster.
- `sectionName` is verplicht op de route. Zonder pin hecht hij zich ook aan de
  HTTP-listener, en omdat een expliciete hostname wint van de hostname-loze
  redirect zou `http://` dan inhoud serveren in plaats van te redirecten.
- Aanzetten verschuift géén verkeer: external-dns laat het bestaande record met
  rust zolang de Ingress bestaat (gemeten 2026-08-17). De cutover is het
  weghalen van de Ingress.
- Nieuwe pagina `docs/GATEWAY-API.md`.

### Gewijzigd — 2026-08-12 (platform-default naar ghcr.io)
- `react-platform/values/common.yaml` — `pwa.image.image` van
  `docker.io/conduction2022/woo-website-v2` naar
  `ghcr.io/conductionnl/woo-website-v2`, en `pwa.image.tag` van
  `V1.0.260422-development` naar `v1.0.0`. Elke nieuwe WOO PWA-frontend landt
  daarmee op ghcr.io zonder per-tenant pin.

  Waarom: het Docker Pro-PAT is op 2026-08-03 verlopen en wordt niet vernieuwd,
  dus de vloot pullt daar weer anoniem onder de limiet van 100 pulls per 6 uur
  per IP — één node-restart trekt tientallen images tegelijk. ghcr.io kent die
  limiet niet voor publieke images en vraagt geen pull-secret (er is er ook geen
  geconfigureerd). Zie `cluster-config/docs/mirror.md`.

  Het commentaarblok erboven is meegegaan: de "huidige pin" noemde
  `development-V1.0.260422` terwijl de waarde `V1.0.260422-development` was
  (omgedraaid), en de gedocumenteerde digest was verouderd. De nieuwe digest
  (`sha256:945b3d05…`) staat er nu bij mét de aantekening dat hij informatief is
  — niets dwingt hem af, de Deployment pullt op tag.

- `react-platform/scripts/smoke-checks.sh` — leest nu ook
  `tenant.frontend.registry` en `.repository` en stelt daar `pwa.image.image`
  van samen, volgens dezelfde regels als `react-tenants.yaml:170-180`
  (registry alleen zinvol mét repository).

  Waarom: het script reproduceerde alleen `tag`. De drie tenants die al op ghcr
  stonden renderden daardoor verkeerd in de lokale fleet-render — het
  verificatiepad was blind voor precies het veld dat deze wijziging gebruikt.

- `docs/ADDING-TENANT.md` — voorbeelden en de veldtabel staan op ghcr.io; de
  nieuwe default is expliciet benoemd, met de waarschuwing dat een tenant die
  alléén een `tag` pint het image-pad uit `common.yaml` erft.
- `docs/ROLLOUTS.md` § "Image-tag bumpen" — de claim dat een bump doorwerkt op
  *alle* tenants gecorrigeerd (tenants zonder pin zijn image-ignore-diffed
  sinds 2026-08-11), plus een nieuwe paragraaf "Registry wisselen".

  Voorwaarde bij deze wijziging: de 23 tenants die alléén een `tag` pinnen
  erven het image-pad uit `common.yaml`, dus zij zouden meeverhuizen naar
  ghcr. Hun tags bestaan daar niet 1-op-1 — `V1.0.260422-development` heet op
  ghcr omgedraaid `development-V1.0.260422`, en `1.0.0` bestaat er niet. Die 23
  hebben in Nextcloud-base daarom eerst een expliciete
  `registry: docker.io` + `repository: conduction2022/woo-website-v2` gekregen
  (nul-diff tegen live). **Landt die commit niet vóór deze, dan stallen 10
  tenants in ImagePullBackOff.**

  Geverifieerd op 2026-08-12: alle 26 gepinde tenants renderen exact de image
  die live draait (0 afwijkingen), `./scripts/verify.sh` groen, geen golden file
  gewijzigd, en een tenant zonder pin rendert
  `ghcr.io/conductionnl/woo-website-v2:v1.0.0` in beide omgevingen.

  Openstaand: de migratie van de 23 legacy Docker Hub-tenants naar ghcr is
  bewust *niet* meegenomen — gefaseerd, canary eerst, 24u soak.

### Gewijzigd — 2026-08-11 (ServerSideDiff op de root-Application)
- `react-platform/argo/applications/root.yaml` — annotatie
  `argocd.argoproj.io/compare-options: ServerSideDiff=true` toegevoegd naast de
  bestaande `ServerSideApply=true`.

  Waarom: server-side apply schrijft geen
  `kubectl.kubernetes.io/last-applied-configuration`, en daar leunt Argo's
  standaard-diff op. Zonder deze optie kan Argo `Synced` melden terwijl live iets
  anders staat, en slaat automated sync daar dus ook niet op aan. Vastgesteld op
  2026-08-11 bij de OLM-app in `ConductionNL/KeyCloak`: die stond maanden
  `Synced` terwijl twee Deployments nooit waren toegepast en een CSV een andere
  versie had.

  Cluster-breed hadden 15 van de 248 apps `ServerSideApply=true` en had er één de
  `ServerSideDiff`-annotatie. Dit is fase 1 van een gefaseerde uitrol; deze app
  beheert drie Argo-objecten (AppProject, ApplicationSet, zichzelf), dus de
  blast radius is klein. Let er bij de eerste sync na de merge op of Argo iets
  bijtrekt dat eerder onzichtbaar bleef.

### Toegevoegd — 2026-08-11 (render-tests voor de ApplicationSet)
- `react-platform/tests/` — golden-file-tests voor de twee Go-templates in de
  `react-tenants` ApplicationSet (`helm.values` en `templatePatch`). Beide zijn
  strings in YAML, dus geen enkele linter zag wat ze rénderen; een fout bleek
  pas op het cluster. Zeven tenant-vormen (geen frontend, alleen tag, alleen
  branding, gepind + branding, BYO-TLS, cert-manager-issuer, extraHosts) × twee
  templates = 14 vergelijkingen. Elke gerenderde uitvoer gaat ook door `yq`, dus
  een template die ongeldige YAML oplevert faalt hier en niet pas bij Argo.

  `scripts/verify.sh` draait de suite mee wanneer `go` beschikbaar is, en meldt
  het expliciet als hij overslaat — een onvolledige verify mag niet groen lijken.

  Mutatietest gedaan: de `$pinned`-conditie omdraaien laat 6 vergelijkingen
  roodslaan, de registry niet meer samenstellen 1.

  BEPERKING: `tests/render/main.go` benadert Argo's engine (Go text/template met
  `missingkey=default` en een handvol nagebouwde sprig-functies). Het bewijst dat
  de templatelogica doet wat we bedoelen, niet dat Argo byte-identiek hetzelfde
  doet. Gebruikt de template een sprig-functie die het harnas niet kent, dan
  faalt het parsen luidruchtig — geen stille divergentie.

### Toegevoegd — 2026-08-11 (per-tenant registry/repository)
- `react-platform/argo/applicationsets/react-tenants.yaml` — `tenant.frontend`
  accepteert nu `registry` en `repository` naast `tag`. De ApplicationSet stelt
  daaruit `<registry>/<repository>:<tag>` samen en levert dat als
  `pwa.image.image` / `pwa.image.tag`. Geen chart-wijziging nodig.

  Drie losse velden i.p.v. één, zodat een provisioningportal geen volledige
  reference in het tag-veld kan proppen. Dat gebeurde op 2026-08-11 bij
  `epe-accept`: `tag: "woo-website-v2:V1.0.260422-development"` rendert als
  `…/woo-website-v2:woo-website-v2:<tag>` en is ongeldig. Nextcloud-base's
  `validate-values.sh` weigert die vorm nu in CI.

### Gewijzigd — 2026-08-11 (image-pin is bindend)
- `react-tenants.yaml` — `ignoreDifferences` is verhuisd naar
  `spec.templatePatch` en is nu per tenant voorwaardelijk:
  - pint een tenant `frontend.registry`/`.repository`/`.tag`, dan wordt de
    image-expressie niet geëmit en reconcilieert Argo de image;
  - heeft een tenant een `frontend.branding`-blok, dan wordt de
    `^(GATSBY_|NL_DESIGN_)`-expressie niet geëmit en reconcilieert Argo de
    branding-env;
  - pint een tenant niets, dan is het gedrag ongewijzigd: live bijstellen in
    de Argo UI blijft mogelijk.

  Waarom via `templatePatch`: met `goTemplate: true` rendert Argo alleen de
  stringvelden van de Application, niet de YAML-structuur — een `{{- if }}` rond
  een key werkt daar niet. `templatePatch` is één string die wél volledig
  getemplate wordt. Let op: een merge-patch vervangt lijsten, dus dat blok is de
  enige vindplaats van `ignoreDifferences`.

  Aanleiding: sinds `5029041` (2026-07-01) was de image altijd ignore-diffed
  voor live self-service tag-bumps. Gevolg was dat een tag die keurig in git
  stond nooit op een bestaande Deployment landde — Argo bleef Synced/Healthy
  terwijl live iets anders draaide. Vastgesteld op `epe-accept` (2026-08-11):
  de Application dróég `pwa.image.tag`, maar de live image bleef de
  platform-default; de goede stand was met de hand gezet via de Argo UI
  (`managedFields` toonde `argocd-server`). Hetzelfde gold voor branding: de
  favicon uit git (`image/png`) stond live als `image/x-icon`.

  Impact: tenants die al een `frontend.tag` in git hadden, kunnen daarvan zijn
  afgeweken. Vóór uitrol is de drift in Nextcloud-base uitgelijnd (git volgt
  live) — zie zijn CHANGELOG van dezelfde datum. Rol deze wijziging niet uit
  zonder die uitlijning.

### 2026-08-03 — pre-commit-hookbron naar GitHub
- `.pre-commit-config.yaml`: de techbook-hook komt van
  `github.com/ConductionNL/techbook` in plaats van `codeberg.org`.
- Aangevuld op 2026-08-11: de pin gaat in dezelfde beweging van commit
  `edf269ee…` naar tag **`v0.2.0`** en de hook `docs-touched` komt erbij.
  Zonder die stap bleef deze repo achter op `monitoring`, `Nextcloud-base`,
  `openwoo-app-config` en `cluster-infra`, die alle vier al op `v0.2.0` zitten of
  daarheen gaan. Alle zes hooks zijn groen over de hele repo.
- Waarom: dit was de laatste harde Codeberg-afhankelijkheid buiten talos.
  Zolang die bestond moest `techbook` naar twee forges gepusht blijven
  worden, en dat is niet volgehouden — 7 van de 9 repos zijn daar uit
  elkaar gelopen. De bron van het patroon zat in
  `techbook/scripts/rollout_precommit_hook.sh`, dat deze URL in élke repo
  schreef; die is in dezelfde ronde omgezet.

### Gewijzigd — 2026-07-13 (eigenaarschap → info@conduction.nl, review WP8)
- Alle `owner:`-front-matter en CODEOWNERS omgezet van `mark` naar
  `info@conduction.nl` (opvolging na 2026-08-31). Voorbereid op branch
  `chore/wp8-ownership`; review, merge en push door een mens.

### Fixed
- **2026-06-30 — theme env key must be GATSBY_-prefixed.** The generator emitted
  `NL_DESIGN_THEME_CLASSNAME`, but the Gatsby app only reads
  `GATSBY_NL_DESIGN_THEME_CLASSNAME` client-side (verified in the JS bundle: 82 refs
  vs 6). So the theme never applied regardless of the classname value or theme asset.
  Renamed the emitted key to `GATSBY_NL_DESIGN_THEME_CLASSNAME` (still covered by the
  `^(GATSBY_|NL_DESIGN_)` ignore-diff). Existing deployments carrying the old un-prefixed
  key are not auto-corrected (ignore-diff freezes branding env) — set the GATSBY_-prefixed
  key live, or recreate the frontend.

### Changed
- **2026-06-30 — theme baseline = `conduction-theme`; branding/theme env is dev-editable LIVE (not GitOps).**
  Per dev request: the `NL_DESIGN_THEME_CLASSNAME` baseline default changed from
  `<org>-theme` to **`conduction-theme`** (which exists in the bundled themes, so it
  renders out of the box). Added `ignoreDifferences` (jqPathExpression matching
  `^(GATSBY_|NL_DESIGN_)` env on the woo-website Deployment) + sync option
  `RespectIgnoreDifferences=true`, so devs adjust branding/theme env **live in Argo**
  without selfHeal reverting or a sync clobbering it. `UPSTREAM_HOST`/`UPSTREAM_BASE`
  stay git-managed. **Trade-off (accepted):** live edits are unaudited, unreviewed, and
  lost if the Deployment is recreated. **Caveat:** frontends already carrying an
  `<org>-theme` value are frozen there by ignore-diff — they won't auto-flip to
  `conduction-theme`; set them live once.

### Fixed
- **2026-06-30 — `NL_DESIGN_THEME_CLASSNAME` now always set on frontends (defaults to `<org>-theme`).**
  The branding env only emitted the NL Design theme classname when a tenant explicitly
  set `frontend.branding.themeClassname`, so onboarded tenants (wassenaar, voorschoten,
  delft, …) rendered without a theme. The generator now derives `$theme` =
  `<org>-theme` (e.g. `wassenaar-theme`) from the tenant name and always emits
  `NL_DESIGN_THEME_CLASSNAME`; `frontend.branding.themeClassname` still overrides it.

### Changed
- **2026-06-30 — frontend TLS now uses the shared wildcard cert (no per-tenant issuance).**
  The `react-tenants` generator no longer puts a `cert-manager.io/cluster-issuer`
  annotation on frontend Ingresses and no longer requests a per-host `<tenant>-tls`
  cert. Instead every frontend references `wildcard-openwoo-tls` — the shared
  `*.openwoo.app` + `*.accept.openwoo.app` cert issued in cluster-infra (DNS-01) and
  reflected into each tenant namespace by reflector. Removes all per-tenant Let's
  Encrypt issuance and its rate-limit pressure. **Depends on cluster-infra**: the
  wildcard cert must be issued and reflected into a namespace before its frontend
  Ingress can serve TLS — deploy cluster-infra first. Once live, the batched rollout
  (batches 2–8) is no longer LE-constrained and may be released freely.

### Removed
- **2026-06-30 — fix(argo): drop `gooisemeren-migrate-prod` frontend (migrate = no frontend).**
  Removed the `tenant-gooisemeren-migrate-prod.yaml` glob from the `react-tenants`
  generator. `*-migrate-*` tenants are TEMPORARY migration backends; the canonical
  tenant's frontend already serves the public host. Here `gooisemeren.openwoo.app` is
  served by the Healthy `gooisemeren-prod-reactfront` (namespace `gooisemeren`), so the
  generated `gooisemeren-migrate-prod-reactfront` only produced a colliding Ingress and
  sat `Missing`. Documented the policy in the generator as a standing rule (and a
  FASE-2 reminder: a `tenant-*.yaml` widening must add an explicit `*-migrate-*`
  exclusion). The orphaned Application + its `woo-website` resources are cleaned up
  manually (generator uses `preserveResourcesOnDeletion: true`).

### Added
- **2026-06-30 — feat(argo): onboard frontend-less WOO tenants (batched for Let's Encrypt).**
  Every WOO tenant should have a frontend. Added globs to the `react-tenants` generator
  for the 34 tenants that had NO `*-reactfront` app (gap computed from the live cluster,
  so no collision with the 44 legacy apps). EXCLUDED on purpose (not WOO portals):
  `vng-backend-*`, `softwarecatalogus-*`, `pipelinq-server-prod`. The 21 tenants already
  on a LEGACY frontend are left untouched (migrated later).
  **Rolled out in batches of ~5** (each frontend mints a `*.openwoo.app` cert; Let's
  Encrypt allows 50 certs/week per registered domain). Release one batch (uncomment its
  lines), push, confirm certs issue, then the next. **Batch 1 (PRIORITY, live):**
  `voorschoten-accept`, `wassenaar-accept`. Batches 2–8 staged (commented) in the
  generator. Longer term, a wildcard `*.openwoo.app` cert removes the per-tenant cert
  pressure entirely.
- **2026-06-24 — feat(argo): onboard `delft-accept` + `edam-volendam-accept` frontends.**
  Added two explicit per-file globs to the `react-tenants` ApplicationSet generator
  (`tenant-delft-accept.yaml`, `tenant-edam-volendam-accept.yaml`). Both are new
  backends with no legacy `*-reactfront` app in `toolchain/` — clean adds, no
  cut-over/downtime. Argo materialises `delft-accept-reactfront`
  (`delft.accept.openwoo.app`) and `edam-volendam-accept-reactfront`
  (`edam-volendam.accept.openwoo.app`) in their existing co-tenant namespaces.
  Branding via `tenant.frontend.branding.organisationName` (set in Nextcloud-base).
- **2026-06-24 — feat(argo): onboard `gooisemeren-migrate-prod` frontend (PROD).**
  Added an explicit per-file glob for the live Gooise Meren prod backend tenant.
  No live frontend existed yet — clean add, no cut-over/downtime. The tenant file
  pins `frontend.host: gooisemeren.openwoo.app` (else the appset derives
  `gooisemeren-migrate.openwoo.app` from the tenant name); upstream auto-follows
  `tenant.hostname` (`gooisemeren.commonground.nu`). Materialises
  `gooisemeren-migrate-prod-reactfront` in the `gooisemeren-migrate-prod` namespace.
- **2026-06-22 — docs(openspec): `frontend-tls-and-migration` change proposal.**
  Design for a per-tenant frontend TLS contract (`tenant.frontend.tls.{secretName,issuer}`,
  written in Nextcloud-base, consumed by the `react-tenants` appset) so the 44 legacy
  `*-reactfront` apps — many on own customer domains, some with bring-your-own certs —
  can be migrated **one tenant at a time** without re-issuing or breaking TLS. Default
  render stays byte-identical. Proposal/design/tasks only; no template change yet.
  See `openspec/changes/frontend-tls-and-migration/`.

### Changed
- **2026-06-21 — fix(argo): allow `*-demo` namespaces in the react-platform AppProject.**
  `conduction-demo` (namespace ends in `-demo`, a valid env suffix that maps to
  accept) was rejected — the AppProject only listed `*-accept`/`*-test`/`*-prod`
  destinations, so `conduction-demo-reactfront` failed with "destination ...
  do not match any of the allowed destinations". Added `*-demo`.
- **2026-06-20 — fix(argo): point the react-platform app-of-apps at HEAD (main).**
  `react-platform/argo/applications/root.yaml` `targetRevision`
  `feat/bootstrap-react-platform` → `HEAD`. The live `react-platform` app drives
  the whole `argo/` dir (AppProject + `react-tenants` appset + root itself) and
  self-heals, so manual `kubectl apply` of the appset was reverted to the old
  branch. Cutover needs a ONE-TIME live patch of the app's `targetRevision`
  (app-of-apps reads its own revision from the old branch); after that it's pure
  GitOps on main.
- **2026-06-20 — feat(argo): roll out conduction test/demo frontends + upstream-follows-backend rule.**
  - Added `tenant-conduction-*.yaml` to the generator glob → new WOO frontends
    for `conduction-test` and `conduction-demo` (no legacy app to cut over).
    Frontend hosts derive to `conduction-{test,demo}.accept.openwoo.app`
    (auto DNS via external-dns + TLS via cert-manager); upstream points at the
    real backend `test.conduction.nl` / `demo.conduction.nl`.
  - **New rule:** the frontend upstream host now follows `tenant.hostname` when
    set (external-domain tenants) so frontend and backend never drift; explicit
    `tenant.frontend.upstreamHost` overrides both. Mirrored in `smoke-checks.sh`.
    Only affects tenants with `tenant.hostname` in the glob (conduction); canary
    (no `tenant.hostname`) is unchanged.
  - Frontends use the platform-default woo-website image (no per-tenant pin);
    pin via `tenant.frontend.tag` if needed. (The dev-tagged openwoo *backend*
    apps are a separate concern — the frontend only calls their API.)
  - Smoke-checks: both render clean (9 resources each, kubeconform valid).
- **2026-06-20 — feat(argo): Nextcloud-base becomes the single source of truth for tenants ("Argo ís de watcher").**
  Branch `feat/nc-base-as-tenant-source`. The `react-tenants` ApplicationSet git
  generator now reads `nextcloud-platform/values/tenants/tenant-*.yaml` from
  `codeberg.org/conduction/Nextcloud-base.git` instead of this repo's own
  `values/tenants/`. Adding a Nextcloud tenant auto-creates its co-tenant WOO
  frontend; the frontend fleet is a pure function of the Nextcloud tenant fleet
  (zero drift, no bespoke watcher process). This repo no longer holds per-tenant
  files — removed `values/tenants/tenant-canary-{accept,prod}.yaml` and
  `values/templates/tenant-template.yaml`; added `values/tenants/README.md`.
  - **Schema:** per-tenant frontend config lives in an optional `tenant.frontend:`
    block in the Nextcloud tenant file (`enabled`, `tag`, `host`, `branding`,
    `env`). Opt-out model: absent block → frontend created with platform defaults.
    `tag` is the per-tenant image pin (the "iffy tags" escape hatch for migration).
  - **Derivation:** Nextcloud `tenant.name` already encodes the environment
    (`almere-accept`), so it maps 1:1 to the namespace and the
    `<name>-reactfront` Application name (== legacy `mcc create-react` output);
    the bare org (`almere`) is stripped via `trimSuffix` for the public hostname only.
  - **Gating:** generator glob is canary-only (`tenant-canary-*.yaml`) for this
    phase — flipping the live appset to this branch touches ONLY canary, an
    apples-to-apples test (canary render is identical to the old source).
  - Added `Nextcloud-base.git` to AppProject `react-platform` `sourceRepos`.
  - Updated `scripts/{smoke-checks,validate-values}.sh`: read the Nextcloud-base
    tenant dir (`TENANTS_DIR`/`TENANT_GLOB` overridable), new derivation, drop the
    tenant file from helm `-f` (the appset no longer passes it), validate the
    `frontend:` block.
  - **Deferred to Fase 2:** widen glob to the full fleet + stage the cut-over of
    the 44 legacy Helm-toolchain frontends (`default` project) per
    `docs/MIGRATION.md`; opt-out *exclusion* mechanism for `enabled:false` tenants
    (a git-files generator cannot skip on a nested field — candidate: a
    `frontend.enabled` gate inside the woo-website chart).
  - Merged onto `main` (trunk-based, no PR); `targetRevision` set to `HEAD` for
    the React-base chart/values sources (generator already tracks Nextcloud-base
    `HEAD`). Canary gating is the generator glob, independent of the revision.
- **chore(argo): migrate source GitHub → Codeberg.** GitHub org `ConductionNL`
  is shadowbanned (`react-platform` + canary reactfront apps `SYNC=Unknown`).
  Repointed `repoURL` `github.com/ConductionNL/React-base` →
  `codeberg.org/Conduction/React-base` in `react-platform/argo/projects/react-platform.yaml`,
  `applicationsets/react-tenants.yaml`, `applications/root.yaml`. Public HTTPS,
  no credentials. GitHub kept for rollback.

### Added

- **2026-05-01** — Initial openspec change `bootstrap-react-platform`. Proposal/design/tasks for mirroring the Nextcloud-base GitOps shape onto the WOO PWA: ApplicationSet + layered Helm values (`common.yaml` → `env/*.yaml` → `tenants/tenant-*.yaml`), vendored `woo-website` chart, AppProject sync-window governance. Replaces the `mcc create-react` per-tenant manifest generator. Tenant files become 2 lines (`name`, `environment`) for the common case; namespace pairs with the Nextcloud co-tenant (`<org>-<env>`); image tag pinned to semver in `common.yaml` (no more `latest`); branding migration sources truth from live cluster state. No code or values scaffolded yet — planning docs only. Files: `openspec/changes/bootstrap-react-platform/{.openspec.yaml,proposal.md,design.md,tasks.md}`.
- **2026-05-01** — Document external dependencies in `bootstrap-react-platform`: DNS handled by `cluster-infra/external-dns` (Cloudflare, `policy: sync`, zones `commonground.nu`/`openwoo.app`/`opencatalogi.nl`) — tenant adds/removes auto-create/auto-reap DNS records. TLS via cert-manager + HTTP-01. Recorded in `design.md` (new "External dependencies" subsection), `proposal.md` (Removed from Scope), and `tasks.md` (task 7.1 will surface this in `docs/ADDING-TENANT.md`).
- **2026-05-01** — Scaffold `react-platform/` (openspec phases 2–7). Vendored `charts/woo-website/` from `woo-website-template-apiv2@b1ac4e89` (refactor branch) plus added `templates/networkpolicy.yaml` for pod-label-scoped default-deny + allow-ingress + allow-egress policies. Wrote `react-platform/values/{common,env/accept,env/prod}.yaml` and `templates/tenant-template.yaml` (image pinned to `1.0.0`, `nodeSelector: role: prod-nextcloud`, ingress className `nginx`, security context platform-grade). Wrote AppProject `react-platform` and ApplicationSet `react-tenants` (mirrors Nextcloud-base shape, namespace `<name>-<env>`, Application name `<name>-<env>-reactfront`). Wrote `scripts/{validate-values,smoke-checks}.sh` (smoke-check reproduces ApplicationSet inline values in bash for offline render testing). Wrote `docs/{ADDING-TENANT,ROLLOUTS,MIGRATION}.md`, `CLAUDE.md`, and updated `README.md`. Synthetic tenant `tenant-test-mcc.yaml` added as canary placeholder; smoke-checks pass (9 resources clean). Phase 1 (cluster discovery) and 8–10 (cut-overs) are deferred to live operations.
