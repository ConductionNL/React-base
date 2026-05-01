# Bootstrap

Eenmalige setup om Argo CD `react-base` te laten zien. Daarna is alles GitOps.

## Voorbereiding

Vereist:
- `kubectl`-context op de target-cluster (Argo CD draait in de `argocd` ns)
- `argocd` CLI gelogd in op die Argo (`argocd login`)
- Repo `https://github.com/ConductionNL/React-base.git` is publiek bereikbaar
  (verifieer met `curl -I https://github.com/ConductionNL/React-base.git`)

## Stappen

### 1. Repo registreren bij Argo CD

```bash
argocd repo add https://github.com/ConductionNL/React-base.git
```

(Geen credentials nodig — public repo, zelfde patroon als
`woo-website-template-apiv2` dat de huidige `*-reactfront` Applications al
gebruiken.)

Verifieer:
```bash
argocd repo list | grep React-base
```

### 2. Root Application deployen

```bash
kubectl apply -f react-platform/argo/applications/root.yaml
```

Dit creëert één Argo Application genaamd `react-platform` (project: default,
namespace: argocd) die `react-platform/argo/` recursief watcht. Argo sync't
vervolgens:
- AppProject `react-platform` (sync-wave -1, dus eerst)
- ApplicationSet `react-tenants` (na de AppProject)
- Zichzelf — `applications/root.yaml` (self-management)

Verifieer:
```bash
kubectl get app -n argocd react-platform
kubectl get appproject -n argocd react-platform
kubectl get appset -n argocd react-tenants
```

### 3. ApplicationSet pakt tenant-bestanden op

Zodra `react-tenants` syncthet, scant hij `react-platform/values/tenants/`
en maakt per `tenant-*.yaml` bestand een Application. De eerste keer:
- `canary-prod-reactfront` (uit `tenant-canary.yaml`)

Verifieer:
```bash
kubectl get app -n argocd canary-prod-reactfront
kubectl get pod,ingress,cert,networkpolicy -n canary-prod -l react.platform/tenant=canary
```

### 4. DNS + TLS auto-provisioning

- `external-dns` (in `cluster-infra`) detecteert de nieuwe Ingress en maakt
  het Cloudflare-record aan voor de hostname.
- `cert-manager` issued een TLS-cert via HTTP-01 challenge zodra DNS staat.

Verifieer:
```bash
dig +short canary.openwoo.app          # moet een IP teruggeven
curl -I https://canary.openwoo.app     # 200 met geldige cert
```

## Branch-context (huidig: testfase op `development`)

Tijdens de canary-validatie wijzen `applications/root.yaml`,
`applicationsets/react-tenants.yaml` en de tenant-source naar
`development`. Zodra de canary stabiel draait, één PR die alle drie naar
`HEAD` (= main) zet, gemerged in een sync window.

Zoek in de repo naar `TODO(post-canary)` — dat zijn de drie locaties.

## Rollback van de bootstrap

Als de bootstrap misgaat (bv. ApplicationSet sync't niet, AppProject
RBAC fout, etc.):

```bash
kubectl delete app -n argocd react-platform   # cascade verwijdert de hele tree
argocd repo rm https://github.com/ConductionNL/React-base.git
```

Workload-pods in `<tenant>-<env>` namespaces blijven achter als
`syncOptions.preserveResourcesOnDeletion` gehonoreerd wordt door de
ApplicationSet (zo geconfigureerd). Verwijder die handmatig als nodig:
```bash
kubectl delete -n canary-prod -l react.platform/tenant=canary all,ingress,networkpolicy,cert
```

## Troubleshooting

| Symptoom | Check |
|---|---|
| `react-platform` Application stuck in OutOfSync / ComparisonError | `argocd app get react-platform` — vaak een YAML-fout in `argo/` |
| ApplicationSet maakt geen Applications | Check generator pad + revision: `kubectl get appset react-tenants -o yaml` |
| Application Healthy maar pod ImagePullBackOff | Image-tag bestaat niet in GHCR — override `pwa.image.tag` in tenant-bestand |
| TLS-cert blijft pending | `kubectl describe cert -n <ns>`; vaak: hostname nog niet via DNS bereikbaar (external-dns ~1 min vertraging) of oude Ingress claimt de host nog |
| DNS-record verschijnt niet op Cloudflare | `kubectl logs -n external-dns deploy/external-dns` — vaak: zone niet in `domainFilters` of token-permissies missen |
