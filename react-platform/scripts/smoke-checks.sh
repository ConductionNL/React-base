#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: tool
#
# react-platform/scripts/smoke-checks.sh — render every WOO PWA tenant against
# the vendored woo-website chart and validate the output with kubeconform.
#
# Source of truth = Nextcloud-base's tenant directory ("Argo ís de watcher").
# This script reproduces the react-tenants ApplicationSet's inline `values:`
# block in bash so the rendered manifest matches what Argo CD produces
# (derived org host, upstream URL, TLS secret, image-tag, branding env).
# Keep in sync with react-platform/argo/applicationsets/react-tenants.yaml.
#
# No cluster required.
#
# Writes: read-only (renders to a temp dir, cleaned on exit)
# Idempotent: yes
# Requires: helm, kubeconform, yq (mikefarah); a Nextcloud-base checkout
#
# Usage:
#   ./react-platform/scripts/smoke-checks.sh
#   TENANTS_DIR=/path/to/Nextcloud-base/nextcloud-platform/values/tenants \
#     ./react-platform/scripts/smoke-checks.sh
#   TENANT_GLOB='tenant-*.yaml' ./react-platform/scripts/smoke-checks.sh   # Fase 2: whole fleet

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHART="${REPO_ROOT}/charts/woo-website"
COMMON="${REPO_ROOT}/react-platform/values/common.yaml"
ENV_DIR="${REPO_ROOT}/react-platform/values/env"

# Tenant truth lives in Nextcloud-base (sibling repo). Override with TENANTS_DIR.
# Default to the canary glob — matches Fase 1 of the appset generator.
TENANTS_DIR="${TENANTS_DIR:-${REPO_ROOT}/../Nextcloud-base/nextcloud-platform/values/tenants}"
TENANT_GLOB="${TENANT_GLOB:-tenant-canary-*.yaml}"

for tool in helm kubeconform yq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "[ERROR] required tool not installed: $tool" >&2
    exit 2
  fi
done

if [[ ! -d "$TENANTS_DIR" ]]; then
  echo "[ERROR] tenant dir not found: $TENANTS_DIR" >&2
  echo "        set TENANTS_DIR to your Nextcloud-base tenants directory" >&2
  exit 2
fi

# Render the ApplicationSet inline-values for one tenant. Mirrors the template
# in react-tenants.yaml — keep both sides in sync.
render_inline_values() {
  local f="$1"
  local ncname env org host upstream_host upstream_base
  ncname="$(yq -r '.tenant.name' "$f")"
  env="$(yq -r '.tenant.environment' "$f")"
  # Nextcloud name encodes env (almere-accept); strip it for the public org host.
  org="${ncname%-"$env"}"

  if [[ "$env" == "prod" ]]; then
    host="${org}.openwoo.app"
    upstream_host="${org}.commonground.nu"
  else
    host="${org}.${env}.openwoo.app"
    upstream_host="${org}.${env}.commonground.nu"
  fi
  upstream_base="https://${upstream_host}/apps/opencatalogi/api"

  # Optional overrides from the frontend block
  local override_host override_api tag
  override_host="$(yq -r '.tenant.frontend.host // ""' "$f")"
  override_api="$(yq -r '.tenant.frontend.apiBaseUrl // ""' "$f")"
  tag="$(yq -r '.tenant.frontend.tag // ""' "$f")"
  [[ -n "$override_host" ]] && host="$override_host"
  [[ -n "$override_api" ]] && upstream_base="$override_api"

  cat <<EOF
commonLabels:
  app.kubernetes.io/part-of: react-platform
  react.platform/tenant: "${ncname}"
  react.platform/environment: "${env}"
global:
  domain: "${host}"
  tls: false
pwa:
EOF

  # Per-tenant image pin (tenant.frontend.tag)
  if [[ -n "$tag" ]]; then
    echo "  image:"
    echo "    tag: \"${tag}\""
  fi

  cat <<EOF
  upstream:
    host: "${upstream_host}"
    base: "${upstream_base}"
  env:
EOF

  # Branding → env vars (only set when present)
  local bname theme jumbo favicon hide
  bname="$(yq -r '.tenant.frontend.branding.organisationName // ""' "$f")"
  theme="$(yq -r '.tenant.frontend.branding.themeClassname // ""' "$f")"
  jumbo="$(yq -r '.tenant.frontend.branding.jumbotronImageUrl // ""' "$f")"
  favicon="$(yq -r '.tenant.frontend.branding.faviconUrl // ""' "$f")"
  hide="$(yq -r '.tenant.frontend.branding.footerHideLogo // ""' "$f")"

  [[ -n "$bname" ]]   && echo "    GATSBY_ORGANISATION_NAME: \"${bname}\""
  [[ -n "$theme" ]]   && echo "    NL_DESIGN_THEME_CLASSNAME: \"${theme}\""
  [[ -n "$jumbo" ]]   && echo "    GATSBY_JUMBOTRON_IMAGE_URL: \"${jumbo}\""
  [[ -n "$favicon" ]] && echo "    GATSBY_FAVICON_URL: \"${favicon}\""
  [[ -n "$hide" && "$hide" != "false" ]] && echo "    GATSBY_FOOTER_HIDE_LOGO: \"${hide}\""

  # Free-form .tenant.frontend.env passthrough
  if [[ "$(yq -r '.tenant.frontend.env // ""' "$f")" != "" ]]; then
    yq -r '.tenant.frontend.env | to_entries[] | "    \(.key): \"\(.value)\""' "$f"
  fi

  cat <<EOF
ingress:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  tls:
    - secretName: "${ncname}-tls"
      hosts:
        - "${host}"
EOF
}

shopt -s nullglob
# shellcheck disable=SC2206  # TENANT_GLOB is intentionally a glob pattern
files=("${TENANTS_DIR}"/${TENANT_GLOB})
shopt -u nullglob

if [[ ${#files[@]} -eq 0 ]]; then
  echo "[WARN] no tenant files match ${TENANTS_DIR}/${TENANT_GLOB}"
  echo "[OK] rendering chart with defaults only"
  helm template woo-website "$CHART" -f "$COMMON" >/dev/null
  echo "[OK] chart renders cleanly"
  exit 0
fi

fail=0
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

for f in "${files[@]}"; do
  base="$(basename "$f")"
  ncname="$(yq -r '.tenant.name // ""' "$f")"
  env="$(yq -r '.tenant.environment // ""' "$f")"
  # Opt-out: a frontend block with enabled:false means no frontend for this tenant.
  enabled="$(yq -r '.tenant.frontend.enabled // "true"' "$f")"
  env_file="${ENV_DIR}/${env}.yaml"

  if [[ -z "$ncname" || -z "$env" ]]; then
    echo "[SKIP] $base: missing tenant.name or tenant.environment"
    fail=1
    continue
  fi

  if [[ "$enabled" == "false" ]]; then
    echo "[SKIP] $base: tenant.frontend.enabled=false (no WOO frontend)"
    continue
  fi

  if [[ ! -f "$env_file" ]]; then
    echo "[FAIL] $base: env file not found: $env_file"
    fail=1
    continue
  fi

  inline="${tmpdir}/inline-${ncname}.yaml"
  render_inline_values "$f" > "$inline"

  echo "→ ${ncname}"
  if ! helm template "${ncname}" "$CHART" \
        -f "$COMMON" \
        -f "$env_file" \
        -f "$inline" 2>"${tmpdir}/helm.err" \
      | kubeconform -strict -summary -ignore-missing-schemas - 2>"${tmpdir}/kc.err"; then
    echo "[FAIL] $base"
    [[ -s "${tmpdir}/helm.err" ]] && cat "${tmpdir}/helm.err"
    [[ -s "${tmpdir}/kc.err" ]] && cat "${tmpdir}/kc.err"
    fail=1
  fi
done

if [[ $fail -ne 0 ]]; then
  echo
  echo "[FAIL] smoke checks failed" >&2
  exit 1
fi

echo
echo "[OK] all render(s) clean"
