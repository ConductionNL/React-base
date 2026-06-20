# tenants/ — intentionally empty

This platform owns **no** per-tenant files. The WOO frontend fleet is derived
from the **single source of truth in Nextcloud-base**:

    Nextcloud-base/nextcloud-platform/values/tenants/tenant-*.yaml

The `react-tenants` ApplicationSet's git generator reads that directory
directly ("Argo ís de watcher"): adding a Nextcloud tenant automatically
creates its co-tenant WOO frontend. Zero drift, no second file to write.

## Per-tenant frontend config

Lives in an optional `tenant.frontend:` block in the **Nextcloud** tenant file
(opt-out — absent block means a frontend is created with platform defaults):

```yaml
tenant:
  name: almere-accept        # already encodes the environment
  environment: accept
  frontend:
    enabled: true            # set false to skip the frontend (internal/test tenants)
    tag: "development-V1.0.260422"   # per-tenant image pin (the "iffy tags" escape hatch)
    host: "woo.almere.nl"    # override derived <org>.openwoo.app (external domains)
    branding:
      organisationName: "Gemeente Almere"
      themeClassname: almere-theme
      jumbotronImageUrl: "https://..."
      faviconUrl: "data:image/png;base64,..."
      footerHideLogo: true
    env:                     # free-form GATSBY_*/NL_DESIGN_* passthrough
      GATSBY_SOMETHING: "x"
```

Everything else (hostname, upstream API URL, TLS secret, namespace) is derived
by the ApplicationSet from `tenant.name` + `tenant.environment`. See
`react-platform/argo/applicationsets/react-tenants.yaml`.
