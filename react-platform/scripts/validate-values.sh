#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: tool
#
# react-platform/scripts/validate-values.sh — validate the WOO frontend inputs
# in the Nextcloud-base tenant files ("Argo ís de watcher": Nextcloud-base is
# the source of truth). Checks the fields the react-tenants ApplicationSet
# consumes: tenant.name, tenant.environment, and the optional tenant.frontend
# block (enabled / tag / branding / host). Nextcloud-base's own validator owns
# the rest; this only covers the frontend-relevant shape it does not know about.
#
# Writes: read-only
# Idempotent: yes
# Requires: yq (mikefarah); a Nextcloud-base checkout
#
# Usage:
#   ./react-platform/scripts/validate-values.sh
#   TENANTS_DIR=/path/to/Nextcloud-base/nextcloud-platform/values/tenants \
#     ./react-platform/scripts/validate-values.sh
#   TENANT_GLOB='tenant-*.yaml' ./react-platform/scripts/validate-values.sh   # Fase 2: whole fleet

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TENANTS_DIR="${TENANTS_DIR:-${REPO_ROOT}/../Nextcloud-base/nextcloud-platform/values/tenants}"
TENANT_GLOB="${TENANT_GLOB:-tenant-canary-*.yaml}"

if ! command -v yq >/dev/null 2>&1; then
  echo "[ERROR] yq is required but not installed (https://github.com/mikefarah/yq)" >&2
  exit 2
fi

if [[ ! -d "${TENANTS_DIR}" ]]; then
  echo "[ERROR] tenant dir not found: ${TENANTS_DIR}" >&2
  echo "        set TENANTS_DIR to your Nextcloud-base tenants directory" >&2
  exit 2
fi

shopt -s nullglob
# shellcheck disable=SC2206  # TENANT_GLOB is intentionally a glob pattern
files=("${TENANTS_DIR}"/${TENANT_GLOB})
shopt -u nullglob

if [[ ${#files[@]} -eq 0 ]]; then
  echo "[OK] no tenant files match ${TENANTS_DIR}/${TENANT_GLOB} — nothing to validate"
  exit 0
fi

fail=0
for f in "${files[@]}"; do
  base="$(basename "$f")"
  file_fail=0

  name="$(yq -r '.tenant.name // ""' "$f")"
  env="$(yq -r '.tenant.environment // ""' "$f")"

  if [[ -z "$name" ]]; then
    echo "[FAIL] $base: missing required field .tenant.name"
    file_fail=1
  elif [[ ! "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
    echo "[FAIL] $base: .tenant.name '$name' must match [a-z0-9]([a-z0-9-]*[a-z0-9])?"
    file_fail=1
  fi

  if [[ -z "$env" ]]; then
    echo "[FAIL] $base: missing required field .tenant.environment"
    file_fail=1
  fi

  # Optional frontend block — validate only what the appset consumes.
  if [[ "$(yq -r 'has("tenant") and (.tenant | has("frontend"))' "$f")" == "true" ]]; then
    enabled="$(yq -r '.tenant.frontend.enabled // ""' "$f")"
    if [[ -n "$enabled" && "$enabled" != "true" && "$enabled" != "false" ]]; then
      echo "[FAIL] $base: .tenant.frontend.enabled must be true or false (got '$enabled')"
      file_fail=1
    fi
    tag="$(yq -r '.tenant.frontend.tag // ""' "$f")"
    if [[ "$(yq -r '.tenant.frontend | has("tag")' "$f")" == "true" && -z "$tag" ]]; then
      echo "[FAIL] $base: .tenant.frontend.tag is set but empty"
      file_fail=1
    fi
  fi

  if [[ $file_fail -eq 0 ]]; then
    # yq (mikefarah) kent geen jq-if/then; keuze in bash.
    if [[ "$(yq -r '.tenant | has("frontend")' "$f")" == "true" ]]; then
      fe="$(yq -r '.tenant.frontend.enabled // "true"' "$f")"
    else
      fe="default-on"
    fi
    echo "[OK] $base ($name / $env, frontend=$fe)"
  else
    fail=1
  fi
done

if [[ $fail -ne 0 ]]; then
  echo
  echo "[FAIL] validation failed" >&2
  exit 1
fi

echo
echo "[OK] all ${#files[@]} tenant file(s) valid"
