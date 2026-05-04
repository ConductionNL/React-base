## Woo PWA Helm chart

This chart deploys the static Woo PWA behind an Ingress and configures the NGINX proxy to route `/api` to your backend.

### Prerequisites
- Kubernetes cluster and `kubectl`
- Helm 3
- Ability to pull from `ghcr.io` for the image tag you choose

### Key values
- `pwa.image.image`: Container image repository (default `ghcr.io/conductionnl/woo-website-v2`)
- `pwa.image.tag`: Image tag (e.g. `helm`, `dev`, or your version)
- `pwa.upstream.host`: Host header for upstream API
- `pwa.upstream.base`: Base URL for upstream API (the proxy will forward `/api/*` here)
- `replicaCount`: Number of replicas
- `global.domain`: Public FQDN for the PWA
- `global.tls`: Whether to add TLS section on the Ingress
- `ingress.*`: Ingress class/annotations/extra hosts and TLS entries

### Quickstart
1) Create an overrides file, for example `values.override.yaml`:

```yaml
pwa:
  image:
    image: ghcr.io/conductionnl/woo-website-v2
    tag: helm
  upstream:
    host: softwarecatalogus.test.commonground.nu
    base: https://softwarecatalogus.test.commonground.nu/apps/opencatalogi/api

global:
  domain: woo.example.org
  tls: true

ingress:
  enabled: true
  className: nginx
  path: /
  tls:
    - secretName: woo-pwa-tls
      hosts:
        - woo.example.org
```

2) Install/upgrade:

```bash
helm upgrade --install woo-pwa ./helm/woo-website -n woo --create-namespace -f values.override.yaml
```

3) Uninstall:

```bash
helm uninstall woo-pwa -n woo
```

### Notes
- The image is a static build of Gatsby. Any `GATSBY_*` variables must be set at image build-time. For most cases, you only need to adjust the runtime proxy via `pwa.upstream.*`.
- If you need a custom theme or other `GATSBY_*` overrides, build your own image from `pwa/Dockerfile` with the appropriate build args, push it, and set `pwa.image.*` to your image and tag.

### Deploy with Argo CD (UI)
- Repository URL: `https://github.com/ConductionNL/woo-website-template-apiv2.git`
- Revision: `container-setup-v1` (or `main` after merge)
- Path: `helm/woo-website`

Values (paste in the UI as Helm parameters or a values block):
```yaml
pwa:
  image:
    image: ghcr.io/conductionnl/woo-website-v2
    tag: helm
  upstream:
    host: softwarecatalogus.test.commonground.nu
    base: https://softwarecatalogus.test.commonground.nu/apps/opencatalogi/api

global:
  domain: woo.example.org
  tls: true

ingress:
  enabled: true
  className: nginx
  path: /
  tls:
    - secretName: woo-pwa-tls
      hosts:
        - woo.example.org
```
# Deploying to a Kubernetes Cluster

In order to install the application in your own cloud environment we support installation in [Kubernetes](https://kubernetes.io) using the supplied [helm](https://helm.sh) chart. Kubernetes is a Container Orchestration Engine that has been standardised for Dutch municipalities under the [Haven](https://haven.commonground.nl) standard, and for which Helm is the default installation method of components.

This helm chart can be installed with the help of Kubernetes Management Tools like [Rancher](https://rancher.com).

This helm chart can be installed by running Helm from your local machine (see instructions on how to install Helm on [helm.sh](https://helm.sh/docs/intro/install/#through-package-managers), which requires to have [kubectl](https://kubernetes.io/docs/tasks/tools/) installed).

If you have Helm and Kubectl installed and you have configured access to your cluster (usually via a kubeconfig file) you can run the following commands to install the application.

```cli
$ helm repo add woo-website 
$ helm install woowebsite woo-website/woo-website
```

The application can be adapted using the following helm values

| Value                       | Description                                                                                                                                        | Default           |
|-----------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------|-------------------|
| `global.domain`             | Sets the domain for the application and its dependencies.                                                                                          | `opencatalogi.nl` |
| `global.tls`                | If the application should request TLS certificates for itself on the domains in `global.domain`, uses a cluster issuer named `letsencrypt-prod`.   | `true`            |


For more information about the helm file for the common gateway see the [installation manual of the common gateway](https://github.com/CommonGateway/CoreBundle/blob/master/docs/features/Installation.md#haven--kubernetes).
Keep in mind that if the common gateway is installed via the subchart of this chart, all values in the manual mentioned should be prefixed by `gateway.`.

## Changelog

- 0.0.1: First version based upon opencatalogi helm file