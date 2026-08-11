#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
# role: tool
#
# react-platform/tests/run-tests.sh — golden-file-tests voor de react-tenants
# ApplicationSet-templates.
#
# De ApplicationSet bevat twee Go-templates die het gedrag per tenant bepalen:
#
#   spec.template.spec.sources[0].helm.values   de Helm-values (image, branding,
#                                               hostnames, TLS-secret)
#   spec.templatePatch                          de voorwaardelijke
#                                               ignoreDifferences
#
# Beide zijn strings in YAML, dus geen enkele linter ziet wat ze rénderen. Deze
# suite rendert ze voor een aantal tenant-vormen (`cases/*.json`) en vergelijkt
# met vastgelegde uitvoer (`golden/`). Een wijziging aan de template die de
# uitvoer verandert, wordt daardoor zichtbaar in de diff van de PR in plaats van
# pas op het cluster.
#
# Elke gerenderde uitvoer wordt bovendien door `yq` gehaald: een template die
# ongeldige YAML oplevert, faalt hier en niet pas bij Argo.
#
# BEPERKING: het renderharnas (render/main.go) benadert Argo's engine — Go
# text/template met missingkey=default en een handvol nagebouwde
# sprig-functies. Het bewijst dat de templatelogica doet wat we bedoelen, niet
# dat Argo byte-identiek hetzelfde doet. Gebruikt de template een sprig-functie
# die het harnas niet kent, dan faalt het parsen luidruchtig.
#
# Writes: golden/ (alleen met --update)
# Idempotent: ja
# Requires: bash, yq, go
#
# Usage:
#   ./run-tests.sh                # alle cases vergelijken met golden/
#   ./run-tests.sh --update       # golden/ herschrijven (bekijk de diff!)
#   ./run-tests.sh --case pinned  # alleen cases waarvan de naam dit bevat

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly CASES_DIR="${SCRIPT_DIR}/cases"
readonly GOLDEN_DIR="${SCRIPT_DIR}/golden"
readonly APPSET="${SCRIPT_DIR}/../argo/applicationsets/react-tenants.yaml"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly NC='\033[0m'

# De twee templates uit de ApplicationSet, met hun yq-pad.
readonly TEMPLATES=(
    "values:.spec.template.spec.sources[0].helm.values"
    "patch:.spec.templatePatch"
)

UPDATE=0
FILTER=""
PASSED=0
FAILED=0

log_pass() { printf "${GREEN}PASS${NC} %s\n" "$1"; }
log_fail() { printf "${RED}FAIL${NC} %s\n" "$1" >&2; }

usage() { sed -n '3,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --update) UPDATE=1; shift ;;
            --case) FILTER="$2"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) echo "error: onbekend argument '$1'" >&2; exit 2 ;;
        esac
    done

    for tool in yq go; do
        command -v "$tool" >/dev/null || { echo "error: $tool ontbreekt" >&2; exit 1; }
    done

    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064  # tmp nu uitvouwen, niet bij trap-uitvoering
    trap "rm -rf '$tmp'" EXIT

    # Templates één keer uit de ApplicationSet halen
    local entry name path
    for entry in "${TEMPLATES[@]}"; do
        name="${entry%%:*}"
        path="${entry#*:}"
        yq eval "$path" "$APPSET" >"${tmp}/${name}.tmpl"
        if [[ ! -s "${tmp}/${name}.tmpl" ]] || [[ "$(cat "${tmp}/${name}.tmpl")" == "null" ]]; then
            echo "error: template '$name' niet gevonden op $path in $APPSET" >&2
            exit 1
        fi
    done

    mkdir -p "$GOLDEN_DIR"

    local case_file case_name out golden
    for case_file in "${CASES_DIR}"/*.json; do
        [[ -e "$case_file" ]] || continue
        case_name="$(basename "$case_file" .json)"
        if [[ -n "$FILTER" ]] && [[ "$case_name" != *"$FILTER"* ]]; then
            continue
        fi

        for entry in "${TEMPLATES[@]}"; do
            name="${entry%%:*}"
            out="${tmp}/${case_name}.${name}.out"
            golden="${GOLDEN_DIR}/${case_name}.${name}.yaml"

            if ! (cd "${SCRIPT_DIR}/render" && go run . "${tmp}/${name}.tmpl" "$case_file") >"$out" 2>"${out}.err"; then
                log_fail "${case_name} [${name}] — renderen faalde"
                sed 's/^/    /' "${out}.err" >&2
                FAILED=$((FAILED + 1))
                continue
            fi

            if ! yq eval '.' "$out" >/dev/null 2>&1; then
                log_fail "${case_name} [${name}] — gerenderde uitvoer is geen geldige YAML"
                sed 's/^/    /' "$out" >&2
                FAILED=$((FAILED + 1))
                continue
            fi

            if [[ "$UPDATE" -eq 1 ]]; then
                cp "$out" "$golden"
                log_pass "${case_name} [${name}] (golden bijgewerkt)"
                PASSED=$((PASSED + 1))
                continue
            fi

            if [[ ! -f "$golden" ]]; then
                log_fail "${case_name} [${name}] — geen golden file; draai --update en bekijk de diff"
                FAILED=$((FAILED + 1))
                continue
            fi

            if diff -u "$golden" "$out" >"${out}.diff"; then
                log_pass "${case_name} [${name}]"
                PASSED=$((PASSED + 1))
            else
                log_fail "${case_name} [${name}] — uitvoer wijkt af van golden:"
                sed 's/^/    /' "${out}.diff" >&2
                FAILED=$((FAILED + 1))
            fi
        done
    done

    echo
    echo "render-tests: ${PASSED} geslaagd, ${FAILED} gefaald"
    [[ $FAILED -eq 0 ]]
}

main "$@"
