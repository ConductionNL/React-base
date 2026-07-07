#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: tool
#
# scripts/verify.sh — snelle functionele verificatie (pre-push gate).
#
# Valideert de HELE tenantvloot (frontend-velden in de Nextcloud-base
# tenant-bestanden), rendert de chart tegen elke tenant en valideert de
# output (smoke-checks + kubeconform), en lint de eigen scripts.
# Dry-run only. Vereist een Nextcloud-base checkout naast deze repo
# (of TENANTS_DIR zetten).
#
# Writes: read-only
# Idempotent: yes
# Requires: yq (mikefarah), kubeconform, helm, shellcheck;
#           ../Nextcloud-base checkout
#
# Usage:
#   ./scripts/verify.sh
#   TENANTS_DIR=/pad/naar/Nextcloud-base/nextcloud-platform/values/tenants ./scripts/verify.sh

set -euo pipefail

cd "$(dirname "$0")/.."

readonly DEFAULT_TENANTS_DIR="../Nextcloud-base/nextcloud-platform/values/tenants"
export TENANTS_DIR="${TENANTS_DIR:-${DEFAULT_TENANTS_DIR}}"
export TENANT_GLOB="tenant-*.yaml"

if [[ ! -d "${TENANTS_DIR}" ]]; then
  echo "verify FAALT: geen Nextcloud-base tenants op ${TENANTS_DIR}" >&2
  echo "  (kloon Nextcloud-base naast deze repo of zet TENANTS_DIR)" >&2
  exit 1
fi

./react-platform/scripts/validate-values.sh >/dev/null
echo "validate-values OK (hele vloot)"

./react-platform/scripts/smoke-checks.sh >/dev/null
echo "smoke-checks OK"

mapfile -t scripts < <(find scripts react-platform/scripts -name '*.sh' -type f | sort)
shellcheck "${scripts[@]}"
echo "shellcheck OK (${#scripts[@]} scripts)"

echo "verify: OK"
