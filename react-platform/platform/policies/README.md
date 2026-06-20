# NetworkPolicies

NetworkPolicies for the WOO PWA pods are templated **inside the vendored
chart** at `charts/woo-website/templates/networkpolicy.yaml`. They ship
per-release and are cleaned up automatically when a tenant Application is
deleted.

This directory is intentionally near-empty: separate platform-policy
manifests would only fit if the policies needed to apply to namespaces
without a tenant Application — which is not the case here. WOO frontends
always come with a release; the policies travel with them.

## Why pod-label scoped?

Tenant namespaces are shared with Nextcloud co-tenants (see
`openspec/changes/bootstrap-react-platform/design.md` Decision 4). The
react NetworkPolicies select pods by `app.kubernetes.io/part-of: react-platform`
so they don't interfere with Nextcloud's own namespace-label-scoped policies.

## What they do

| Policy | Direction | Allowed |
|---|---|---|
| `default-deny`     | both     | nothing — baseline lockdown |
| `allow-ingress`    | ingress  | from `ingress-nginx` ns to pod port 8080 |
| `allow-egress`     | egress   | DNS to `kube-system`; HTTPS (443) to public IPs only (RFC1918 ranges blocked to prevent in-cluster lateral movement) |

## Toggling off

For testing or clusters without NetworkPolicy enforcement, set in tenant or env values:

```yaml
networkPolicy:
  enabled: false
```
