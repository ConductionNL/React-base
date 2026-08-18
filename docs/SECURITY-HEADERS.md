---
last_reviewed: 2026-08-18
owner: info@conduction.nl
---

# Security-headers en certificaatsleutel

Referentie bij de audit-set die internet.nl controleert. Aanleiding: audit op
`open.dinkelland.nl`, gemeten 2026-08-18. Ontbraken toen:
`Content-Security-Policy`, `X-Frame-Options`, `Referrer-Policy`. Het certificaat
was Let's Encrypt RSA-2048, in de audit als phase-out aangemerkt.

## Waar de headers vandaan komen

Eén bron: `securityHeaders.headers` in `charts/woo-website/values.yaml`. Die map
rendert op **twee** datapaden, zodat een tenant tijdens de Gateway-migratie via
beide dezelfde headers krijgt:

| Pad | Mechanisme |
|---|---|
| Ingress (ingress-nginx) | annotatie `nginx.ingress.kubernetes.io/configuration-snippet` met `more_set_headers` |
| HTTPRoute (Envoy Gateway) | `filters: ResponseHeaderModifier.set` op de rule |

Beide **zetten** een header en plakken er geen tweede bij (anders dan nginx'
`add_header`). Wat de pod zelf al stuurt blijft dus enkelvoudig.

`custom-headers` — de niet-snippet-annotatie van ingress-nginx 1.12 — is bekeken
en afgevallen: die eist eerst `global-allowed-response-headers` in de globale
controller-ConfigMap, en die ConfigMap staat in geen enkele repo.

## Wat hier níét vandaan komt

- `Strict-Transport-Security` — komt van ingress-nginx zelf (default `hsts: true`,
  `max-age=31536000`, `includeSubdomains`).
- `X-Content-Type-Options: nosniff` — komt van de nginx in de pod (image).

Ze staan daarom niet in `securityHeaders`. Voeg ze niet toe zonder eerst te
meten wat er live over de lijn komt.

## CSP staat op Report-Only

De waarde staat onder `Content-Security-Policy-Report-Only`, niet onder
`Content-Security-Policy`. Reden, gemeten in de live bundel van
`open.dinkelland.nl`:

- één inline `<script>` (de Gatsby-loader; de hash wisselt per build, dus een
  `sha256-`-allowlist is niet houdbaar) → `script-src 'unsafe-inline'`;
- 39 inline `style=`-attributen → `style-src 'unsafe-inline'`;
- fonts van `fonts.gstatic.com` en `db.onlinewebfonts.com`;
- branding-afbeeldingen van een externe host, per tenant verschillend
  (dinkelland gebruikt `raw.githubusercontent.com`);
- de API-calls gaan naar de upstream onder `*.commonground.nu`.

Enforcen zonder te meten breekt de site stil: een geblokkeerde bundel geeft een
witte pagina, geen foutmelding. Naar enforce toe werken doe je per tenant:

1. open de site met de devtools-console open en verzamel de
   `Report-Only`-overtredingen;
2. vul de ontbrekende bronnen aan in `securityHeaders.headers`;
3. hernoem de key naar `Content-Security-Policy` als er niets meer overblijft.

Een tenant met een eigen `jumbotronImageUrl` op een andere host heeft eigen
bronnen nodig — dat is de reden dat enforce per tenant gaat en niet vloot-breed.

## Sleutel van het certificaat

De ApplicationSet zet bij de issuer-tak van `frontend.tls` twee annotaties op de
Ingress: `cert-manager.io/private-key-algorithm: ECDSA` en
`private-key-size: "256"`. Cert-manager (v1.18 op dit cluster) zet die door naar
de Certificate.

Dat is een wijziging van de Certificate-spec, dus **elke tenant met een eigen
certificaat krijgt éénmalig een nieuw certificaat**. Custom-domain tenants zijn
losse registered domains, dus de Let's Encrypt-limiet van 50 per registered
domain per week speelt hier niet. Tenants onder het gedeelde
`wildcard-openwoo-tls` raakt dit niet: dat certificaat leeft in `cluster-infra`.

## Buiten deze repo

| Bevinding | Waar het hoort |
|---|---|
| TLS 1.2 accepteert `rsa_pkcs1_sha224` | `http-snippet` in de ingress-nginx controller-ConfigMap (release `nginx`, in geen repo), of `ClientTrafficPolicy.tls.signatureAlgorithms` in `cluster-infra` voor het Gateway-pad |
| CAA-record, AAAA-record, DANE/TLSA | de eigenaar van de zone; bij een custom domain is dat de gemeente, niet wij |
| Ondertekende `security.txt` | per tenant via `frontend.wellKnown`, zie `ADDING-TENANT.md` |

## Verifiëren

    curl -sSI https://<host>/ | grep -iE 'content-security|x-frame|referrer|strict-transport|x-content-type'

    echo | openssl s_client -connect <host>:443 -servername <host> 2>/dev/null \
      | openssl x509 -noout -subject -issuer -dates -text | grep -E 'Public-Key|Signature Algorithm'

    echo | openssl s_client -connect <host>:443 -servername <host> -tls1_2 -sigalgs RSA+SHA224 2>&1 \
      | grep -E 'Peer signature type|alert'

De laatste hoort ná de nginx-wijziging een handshake failure te geven; geeft hij
`Peer signature type: rsa_pkcs1_sha224`, dan staat SHA-224 nog open.
