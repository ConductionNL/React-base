#!/usr/bin/env bash
# bootstrap.sh — eenmalige bootstrap van react-base op een Argo CD cluster.
#
# Doet:
#  1. Sanity-checks (kubectl context, argocd ns, repo bereikbaar)
#  2. Registreer React-base repo bij Argo CD (Secret in argocd ns)
#  3. Apply root App-of-Apps Application
#  4. Print status
#
# Idempotent — herhaaldelijk runnen is veilig (gebruikt `kubectl apply`).
#
# Usage:
#   ./react-platform/scripts/bootstrap.sh
#
# Variabelen (override via env):
#   ARGOCD_NS    default: argocd
#   REPO_URL     default: https://github.com/ConductionNL/React-base.git
#   REPO_SECRET  default: react-base-repo

set -euo pipefail

ARGOCD_NS="${ARGOCD_NS:-argocd}"
REPO_URL="${REPO_URL:-https://github.com/ConductionNL/React-base.git}"
REPO_SECRET="${REPO_SECRET:-react-base-repo}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT_APP_MANIFEST="${REPO_ROOT}/react-platform/argo/applications/root.yaml"

step() { echo; echo "===> $*"; }
ok()   { echo "[OK]  $*"; }
fail() { echo "[FAIL] $*"; exit 1; }

# ---------------------------------------------------------------------------
step "Sanity checks"
# ---------------------------------------------------------------------------

command -v kubectl >/dev/null 2>&1 || fail "kubectl not found in PATH"

CTX="$(kubectl config current-context 2>/dev/null || true)"
[[ -n "$CTX" ]] || fail "no kubectl context — run 'kubectl config use-context <name>' first"
ok "kubectl context: $CTX"

kubectl get ns "$ARGOCD_NS" >/dev/null 2>&1 \
  || fail "namespace '$ARGOCD_NS' not found — is Argo CD installed here?"
ok "argocd namespace: $ARGOCD_NS"

if ! curl -fsS -o /dev/null --max-time 5 "${REPO_URL%.git}.git/info/refs?service=git-upload-pack"; then
  fail "repo not reachable: $REPO_URL (public clone test failed)"
fi
ok "repo reachable: $REPO_URL"

[[ -f "$ROOT_APP_MANIFEST" ]] \
  || fail "root Application manifest not found: $ROOT_APP_MANIFEST"
ok "root manifest: $ROOT_APP_MANIFEST"

# ---------------------------------------------------------------------------
step "Registreer repo bij Argo CD"
# ---------------------------------------------------------------------------

if kubectl get secret -n "$ARGOCD_NS" "$REPO_SECRET" >/dev/null 2>&1; then
  ok "Secret '$REPO_SECRET' bestaat al — apply (idempotent)"
else
  ok "Secret '$REPO_SECRET' nog niet aanwezig — wordt aangemaakt"
fi

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${REPO_SECRET}
  namespace: ${ARGOCD_NS}
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: ${REPO_URL}
EOF

ok "repo geregistreerd"

# ---------------------------------------------------------------------------
step "Deploy root App-of-Apps Application"
# ---------------------------------------------------------------------------

kubectl apply -f "$ROOT_APP_MANIFEST"
ok "root Application applied"

# ---------------------------------------------------------------------------
step "Wacht op eerste sync (max ~60s)"
# ---------------------------------------------------------------------------

for i in {1..30}; do
  STATUS="$(kubectl get app -n "$ARGOCD_NS" react-platform \
    -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || echo 'pending')"
  if [[ "$STATUS" == "Synced/Healthy" ]]; then
    ok "react-platform: Synced/Healthy"
    break
  fi
  echo "  ... [$i/30] status=$STATUS"
  sleep 2
done

# ---------------------------------------------------------------------------
step "Eindstand"
# ---------------------------------------------------------------------------

echo
echo "Argo resources die nu beheerd worden:"
kubectl get app,appset,appproject -n "$ARGOCD_NS" -l app.kubernetes.io/part-of=react-platform 2>&1 || true

echo
echo "Tenant Applications gegenereerd door react-tenants ApplicationSet:"
kubectl get app -n "$ARGOCD_NS" -l react.platform/tenant 2>&1 || true

echo
echo "Eerste tenant (canary) workload-state:"
kubectl get pod,ingress,cert,networkpolicy -n canary-prod -l react.platform/tenant=canary 2>&1 || true

echo
ok "bootstrap klaar — zie BOOTSTRAP.md voor verificatie-stappen"
