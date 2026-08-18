---
last_reviewed: 2026-08-17
owner: info@conduction.nl
---

# Gateway API-route voor een frontend-tenant

Het platform migreert van ingress-nginx (upstream gearchiveerd, geen
CVE-patches meer) naar Gateway API met Envoy Gateway. De achtergrond en de
platformkant staan in `cluster-infra/docs/gateway-api.md`; deze pagina gaat over
wat een frontend-tenant ervoor nodig heeft.

## De verdeling

Cluster-infra bezit de `Gateway`. Deze repo bezit de **route** van een
frontend-tenant: `charts/woo-website/templates/httproute.yaml`, gerenderd door
dezelfde ApplicationSet die vandaag zijn Ingress rendert. Cluster-infra heeft
daardoor geen schrijfrecht in tenant-namespaces nodig.

## Aanzetten

In het tenant-bestand — dat staat in **Nextcloud-base**, niet hier
(`nextcloud-platform/values/tenants/tenant-<naam>.yaml`):

    gateway:
      frontend: true

Meer is het niet voor een host onder `*.openwoo.app` of
`*.accept.openwoo.app`. Die vallen onder het gedeelde wildcard-certificaat en
hangen aan de bestaande listener `https-openwoo`.

Een **custom-domain** tenant (bijvoorbeeld `acceptatie-open.gooisemeren.nl`)
valt daar niet onder en heeft een eigen listener op de Gateway nodig, met een
eigen `certificateRef`. Verwijs er dan naar:

    gateway:
      frontend: true
      frontendSectionName: https-gooisemeren

Let op het `frontend`-voorvoegsel. Het blok `tenant.gateway` wordt gedeeld met de
Nextcloud-route, en die heeft zijn eigen `sectionName` naar een heel andere
listener — andere hostname, ander certificaat. Op 2026-08-18 deelden beide één
veld, waardoor de frontend van canary-accept aan de commonground.nu-listener werd
gehangen en de route op `Accepted=False (NoMatchingListenerHostname)` kwam. De
testcase `gateway-route-nextcloud-sectionname-ignored` bewaakt dat nu.

Zonder `gateway:`-blok rendert er niets extra's — ook geen `enabled: false`.
Dat is opzet: een blok dat altijd meegaat zou alle 84 tenant-Applications
tegelijk laten hersyncen.

## Wat er dan gebeurt — en wat níét

De HTTPRoute komt náást de Ingress te staan. Beide blijven bestaan.

Wat er **niet** gebeurt: het verkeer verschuift niet. Het DNS-record blijft naar
ingress-nginx wijzen, want external-dns laat een bestaand record met rust zolang
de Ingress bestaat — bij twee bronnen voor dezelfde hostname wint de eerste
resource. Gemeten 2026-08-17.

**De cutover is dus het weghalen van de Ingress, niet het bijzetten van de
route.** Pas dan verhuist het record. Dat is ook het punt van geen terugweg:
terugdraaien is daarna een tweede DNS-wijziging.

## Valideren vóór de cutover

Een `curl` op de hostnaam raakt nog nginx, dus dat bewijst niets. Forceer de
resolutie naar het adres van de Gateway (`kubectl get svc -n envoy-gateway-system`):

    IP=81.24.11.239
    H=<tenant>.accept.openwoo.app
    curl -sI --resolve "$H:443:$IP" "https://$H/"
    curl -sI --resolve "$H:80:$IP"  "http://$H/"

Verwacht: 200 met een geldig certificaat, en 308 op poort 80. Draai daarna
dezelfde twee zonder `--resolve` en vergelijk.

Frontends dragen geen enkele nginx-annotatie, dus er valt verder niets te
vertalen: één host, één backend, geen filters. Dat maakt ze geschikt als eerste
stap en ongeschikt om iets over de Nextcloud-migratie te bewijzen.

## Tests

`react-platform/tests/` rendert de ApplicationSet-templates tegen vastgelegde
tenantvormen. De cases `gateway-route` en `gateway-route-sectionname` dekken
beide varianten. Verandert de template de uitvoer van een bestaande tenant, dan
valt dat in de diff van de PR — precies wat je wilt weten bij een generator die
84 tenants voedt.
