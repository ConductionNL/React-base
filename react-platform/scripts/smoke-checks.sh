#!/usr/bin/env bash
# smoke-checks.sh — render every tenant against the vendored chart and
# pipe through kubeconform for K8s schema validation. No cluster required.
#
# Run from repo root:
#   ./react-platform/scripts/smoke-checks.sh
#
# This script reproduces the ApplicationSet's inline `values:` block in
# bash so the rendered manifest matches what Argo CD would actually
# produce (hostname, upstream URL, TLS secret name, branding env vars).
# Keep in sync with react-platform/argo/applicationsets/react-tenants.yaml.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHART="${REPO_ROOT}/charts/woo-website"
COMMON="${REPO_ROOT}/react-platform/values/common.yaml"
TENANTS_DIR="${REPO_ROOT}/react-platform/values/tenants"
ENV_DIR="${REPO_ROOT}/react-platform/values/env"

for tool in helm kubeconform yq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "[ERROR] required tool not installed: $tool"
    exit 2
  fi
done

# Render the ApplicationSet inline-values for one tenant. Mirrors the
# template in react-tenants.yaml — keep both sides in sync.
render_inline_values() {
  local f="$1"
  local name env host upstream_host upstream_base
  name="$(yq -r '.tenant.name' "$f")"
  env="$(yq -r '.tenant.environment' "$f")"

  if [[ "$env" == "prod" ]]; then
    host="${name}.openwoo.app"
    upstream_host="${name}.commonground.nu"
  else
    host="${name}.${env}.openwoo.app"
    upstream_host="${name}.${env}.commonground.nu"
  fi
  upstream_base="https://${upstream_host}/apps/opencatalogi/api"

  # Optional overrides
  local override_host override_api
  override_host="$(yq -r '.tenant.hostname // ""' "$f")"
  override_api="$(yq -r '.tenant.apiBaseUrl // ""' "$f")"
  [[ -n "$override_host" ]] && host="$override_host"
  [[ -n "$override_api" ]] && upstream_base="$override_api"

  cat <<EOF
commonLabels:
  app.kubernetes.io/part-of: react-platform
  react.platform/tenant: "${name}"
  react.platform/environment: "${env}"
global:
  domain: "${host}"
  tls: true
pwa:
  upstream:
    host: "${upstream_host}"
    base: "${upstream_base}"
  env:
EOF

  # Branding → env vars (only set when present)
  local org theme jumbo favicon hide
  org="$(yq -r '.tenant.branding.organisationName // ""' "$f")"
  theme="$(yq -r '.tenant.branding.themeClassname // ""' "$f")"
  jumbo="$(yq -r '.tenant.branding.jumbotronImageUrl // ""' "$f")"
  favicon="$(yq -r '.tenant.branding.faviconUrl // ""' "$f")"
  hide="$(yq -r '.tenant.branding.footerHideLogo // ""' "$f")"

  [[ -n "$org" ]]    && echo "    GATSBY_ORGANISATION_NAME: \"${org}\""
  [[ -n "$theme" ]]  && echo "    NL_DESIGN_THEME_CLASSNAME: \"${theme}\""
  [[ -n "$jumbo" ]]  && echo "    GATSBY_JUMBOTRON_IMAGE_URL: \"${jumbo}\""
  [[ -n "$favicon" ]] && echo "    GATSBY_FAVICON_URL: \"${favicon}\""
  [[ -n "$hide" && "$hide" != "false" ]] && echo "    GATSBY_FOOTER_HIDE_LOGO: \"${hide}\""

  # Free-form .tenant.env passthrough
  if [[ "$(yq -r '.tenant.env // ""' "$f")" != "" ]]; then
    yq -r '.tenant.env | to_entries[] | "    \(.key): \"\(.value)\""' "$f"
  fi

  cat <<EOF
ingress:
  hosts:
    - host: "${host}"
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls:
    - secretName: "${name}-${env}-tls"
      hosts:
        - "${host}"
EOF
}

shopt -s nullglob
files=("${TENANTS_DIR}"/tenant-*.yaml)
shopt -u nullglob

if [[ ${#files[@]} -eq 0 ]]; then
  echo "[OK] no tenant files yet — rendering chart with defaults only"
  helm template woo-website "$CHART" -f "$COMMON" >/dev/null
  echo "[OK] chart renders cleanly"
  exit 0
fi

fail=0
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

for f in "${files[@]}"; do
  base="$(basename "$f")"
  name="$(yq -r '.tenant.name // ""' "$f")"
  env="$(yq -r '.tenant.environment // ""' "$f")"
  env_file="${ENV_DIR}/${env}.yaml"

  if [[ -z "$name" || -z "$env" ]]; then
    echo "[SKIP] $base: missing tenant.name or tenant.environment (run validate-values.sh)"
    fail=1
    continue
  fi

  if [[ ! -f "$env_file" ]]; then
    echo "[FAIL] $base: env file not found: $env_file"
    fail=1
    continue
  fi

  inline="${tmpdir}/inline-${name}-${env}.yaml"
  render_inline_values "$f" > "$inline"

  echo "→ ${name} (${env})"
  if ! helm template "${name}-${env}" "$CHART" \
        -f "$COMMON" \
        -f "$env_file" \
        -f "$f" \
        -f "$inline" 2>/tmp/helm.err \
      | kubeconform -strict -summary -ignore-missing-schemas - 2>/tmp/kc.err; then
    echo "[FAIL] $base"
    [[ -s /tmp/helm.err ]] && cat /tmp/helm.err
    [[ -s /tmp/kc.err ]] && cat /tmp/kc.err
    fail=1
  fi
done

if [[ $fail -ne 0 ]]; then
  echo
  echo "[FAIL] smoke checks failed"
  exit 1
fi

echo
echo "[OK] all ${#files[@]} tenant render(s) clean"
