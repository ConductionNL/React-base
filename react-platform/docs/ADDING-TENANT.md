# Tenant toevoegen

Een nieuwe WOO PWA-tenant aanmelden duurt twee minuten en is pure GitOps —
geen `kubectl`, geen Cloudflare, geen TLS-handelingen.

## Stappen

1. Kopieer `react-platform/values/templates/tenant-template.yaml` naar
   `react-platform/values/tenants/tenant-<naam>-<environment>.yaml`
   (bv. `tenant-almere-accept.yaml`, `tenant-almere-prod.yaml`).
2. Vul minimaal in:
   ```yaml
   tenant:
     name: <naam>
     environment: accept   # of: prod
   ```
3. (Optioneel) Voeg branding-overrides toe — zie de template voor de
   beschikbare velden.
4. Commit + push. Open een PR.
5. Na merge pakt de ApplicationSet `react-tenants` het bestand automatisch
   op en maakt een Argo CD Application aan (`<naam>-<environment>-reactfront`).

## Wat gebeurt er automatisch?

| Stap | Door wie |
|---|---|
| Argo Application aanmaken | ApplicationSet `react-tenants` |
| Namespace gebruiken | Bestaande co-tenant namespace `<naam>-<environment>` (Nextcloud-base) |
| Hostname genereren | ApplicationSet template — `<naam>.openwoo.app` (prod) of `<naam>.accept.openwoo.app` (accept) |
| DNS-record op Cloudflare | `cluster-infra/external-dns` (auto-create) |
| TLS-certificaat | cert-manager via HTTP-01 |
| NetworkPolicies | Vendored chart `templates/networkpolicy.yaml` |
| Pod-placement | `nodeSelector: role: prod-nextcloud` (zie `values/common.yaml`) |

**Geen actie nodig op Cloudflare**, geen TLS-secret aanmaken, geen DNS-edits.
External-DNS reageert op de Ingress die de chart deployt.

## Voorwaarde: namespace bestaat al

De frontend-pod landt in dezelfde namespace als de Nextcloud-tenant
(bijvoorbeeld `almere-accept` of `almere-prod`). Die namespace wordt
beheerd door `Nextcloud-base` en moet er zijn vóór de eerste sync van
deze frontend.

Verifieer met:
```bash
kubectl get ns <naam>-<environment>
```

Als de namespace ontbreekt: er is geen Nextcloud co-tenant in deze
omgeving. Maak die eerst aan via `Nextcloud-base` (`values/tenants/`
add tenant), of maak de namespace handmatig met label
`app.kubernetes.io/part-of: nextcloud-platform`.

## Voorbeelden

### Minimale tenant (geen branding)
```yaml
tenant:
  name: test-mcc
  environment: accept
```

### Tenant met branding (Almere-stijl)
```yaml
tenant:
  name: almere
  environment: accept
  branding:
    organisationName: "Gemeente Almere"
    themeClassname: almere-theme
    footerHideLogo: true
    jumbotronImageUrl: "https://..."
    faviconUrl: "data:image/png;base64,..."
```

### Tenant met afwijkende hostname
```yaml
tenant:
  name: speciaal
  environment: prod
  hostname: woo.speciaal.gemeente.nl   # override van convention
```

## Validatie vóór commit

Voer beide scripts uit voor je een PR opent:

```bash
./react-platform/scripts/validate-values.sh
./react-platform/scripts/smoke-checks.sh
```

`validate-values.sh` controleert vereiste velden en filename-conventie.
`smoke-checks.sh` rendert de chart met je tenant-config en valideert
het resultaat tegen Kubernetes-schema's.

## Verwijderen

1. Verwijder `react-platform/values/tenants/tenant-<naam>.yaml`.
2. Commit + push + merge.
3. Verwijder de bijbehorende Application **handmatig** in Argo CD —
   `preserveResourcesOnDeletion: true` in de ApplicationSet voorkomt
   per ongeluk verwijderen. Met cascade verdwijnt de Deployment, Service,
   Ingress, NetworkPolicies, en cert-manager Cert. external-DNS reapt
   het Cloudflare-record.
