#!/usr/bin/env bash
# validate-values.sh — required-field check for tenant YAML files.
#
# Run from repo root:
#   ./react-platform/scripts/validate-values.sh
#
# Exit 0 = all tenants valid. Non-zero = something failed; per-file
# failures are printed before exit.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TENANTS_DIR="${REPO_ROOT}/react-platform/values/tenants"

if ! command -v yq >/dev/null 2>&1; then
  echo "[ERROR] yq is required but not installed (https://github.com/mikefarah/yq)"
  exit 2
fi

if [[ ! -d "${TENANTS_DIR}" ]]; then
  echo "[ERROR] tenants dir not found: ${TENANTS_DIR}"
  exit 2
fi

shopt -s nullglob
files=("${TENANTS_DIR}"/tenant-*.yaml)
shopt -u nullglob

if [[ ${#files[@]} -eq 0 ]]; then
  echo "[OK] no tenant files yet — nothing to validate"
  exit 0
fi

fail=0
for f in "${files[@]}"; do
  base="$(basename "$f")"

  name="$(yq -r '.tenant.name // ""' "$f")"
  env="$(yq -r '.tenant.environment // ""' "$f")"

  if [[ -z "$name" ]]; then
    echo "[FAIL] $base: missing required field .tenant.name"
    fail=1
  elif [[ ! "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
    echo "[FAIL] $base: .tenant.name '$name' must match [a-z0-9]([a-z0-9-]*[a-z0-9])?"
    fail=1
  fi

  if [[ -z "$env" ]]; then
    echo "[FAIL] $base: missing required field .tenant.environment"
    fail=1
  elif [[ "$env" != "accept" && "$env" != "prod" ]]; then
    echo "[FAIL] $base: .tenant.environment must be 'accept' or 'prod' (got '$env')"
    fail=1
  fi

  # Convention check: filename = tenant-<name>-<env>.yaml.
  # Uniek per (org, env) combinatie zodat dezelfde tenant.name kan bestaan
  # voor zowel accept als prod zonder filename-collision.
  expected="tenant-${name}-${env}.yaml"
  if [[ -n "$name" && -n "$env" && "$base" != "$expected" ]]; then
    echo "[FAIL] $base: filename should be '$expected' (tenant-<name>-<env>.yaml)"
    fail=1
  fi

  if [[ $fail -eq 0 ]]; then
    echo "[OK] $base ($name / $env)"
  fi
done

if [[ $fail -ne 0 ]]; then
  echo
  echo "[FAIL] validation failed"
  exit 1
fi

echo
echo "[OK] all ${#files[@]} tenant file(s) valid"
