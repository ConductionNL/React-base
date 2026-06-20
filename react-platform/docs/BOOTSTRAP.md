# Bootstrap

Eenmalige setup om Argo CD `react-base` te laten zien. Daarna is alles GitOps.

Pure `kubectl`-pattern, identiek aan hoe Nextcloud-base is gebootstrapped
(geen `argocd` CLI nodig — `argocd-sync.sh` daar gebruikt ook alleen
kubectl-annotations).

## Voorbereiding

Vereist:
- `kubectl`-context op de target-cluster (Argo CD draait in `argocd` ns)
- Repo `https://github.com/ConductionNL/React-base.git` is publiek bereikbaar

## Snelle weg: `./react-platform/scripts/bootstrap.sh`

```bash
./react-platform/scripts/bootstrap.sh
```

Dat script:
1. Doet sanity-checks (kubectl context, argocd ns aanwezig, repo bereikbaar)
2. Registreert de repo (`Secret` met label `argocd.argoproj.io/secret-type=repository`)
3. Apply't `react-platform/argo/applications/root.yaml` — de root App-of-Apps
4. Wacht ~60s op de eerste sync
5. Print eindstand (apps, appsets, project, canary tenant pods)

Idempotent — herhaaldelijk runnen is veilig.

## Wat de bootstrap stap-voor-stap doet (als je het zonder script wil)

### 1. Repo registreren bij Argo CD

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: react-base-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: https://github.com/ConductionNL/React-base.git
EOF
```

Niet committen — zelfde patroon als Nextcloud-base
(`repo-3511387122` en `nextcloud-repo-key` zijn enkel cluster-state).

### 2. Root Application deployen

```bash
kubectl apply -f react-platform/argo/applications/root.yaml
```

Dit creëert één Argo Application genaamd `react-platform` (project:
default, namespace: argocd) die `react-platform/argo/` recursief watcht.
Argo sync't vervolgens:
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

## Branch-context (huidig: testfase op `feat/bootstrap-react-platform`)

Tijdens de canary-validatie wijzen `applications/root.yaml` (1×) en
`applicationsets/react-tenants.yaml` (3×) naar de feature branch. Reden:
GitHub repository rules eisen PR-review voor `development` en `main`,
dus we kunnen daar niet rechtstreeks naar pushen tijdens de iteratie.
Argo pulled rustig vanaf de feature branch.

Zodra de canary stabiel draait: één PR die alle vier locaties naar
`HEAD` (= main) zet, gemerged in een sync window.

Zoek in de repo naar `TODO(post-canary)` — dat zijn de vier locaties.

## Sync forceren tijdens iteratie

Voor snellere feedback kun je een hard refresh + sync forceren via
kubectl-annotations (zelfde patroon als
`Nextcloud-base/nextcloud-platform/scripts/argocd-sync.sh`):

```bash
# Refresh root application
kubectl annotate app -n argocd react-platform \
  argocd.argoproj.io/refresh=hard --overwrite

# Refresh ApplicationSet generator (force re-scan tenant files)
kubectl annotate appset -n argocd react-tenants \
  argocd.argoproj.io/refresh=true --overwrite
```

## Rollback van de bootstrap

Als de bootstrap misgaat (bv. ApplicationSet sync't niet, AppProject
RBAC fout, etc.):

```bash
kubectl delete app -n argocd react-platform   # cascade verwijdert de hele tree
kubectl delete secret -n argocd react-base-repo
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
| `react-platform` Application stuck in OutOfSync / ComparisonError | `kubectl describe app -n argocd react-platform` — vaak een YAML-fout in `argo/` |
| ApplicationSet maakt geen Applications | `kubectl get appset -n argocd react-tenants -o yaml` — check generator pad + revision |
| Application Healthy maar pod ImagePullBackOff | Image-tag bestaat niet in GHCR — override `pwa.image.tag` in tenant-bestand |
| TLS-cert blijft pending | `kubectl describe cert -n <ns>`; vaak: hostname nog niet via DNS bereikbaar (external-dns ~1 min vertraging) of oude Ingress claimt de host nog |
| DNS-record verschijnt niet op Cloudflare | `kubectl logs -n external-dns deploy/external-dns` — vaak: zone niet in `domainFilters` of token-permissies missen |
