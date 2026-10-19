#!/usr/bin/env bash
# Deploys the Angular frontend to the OpenShift project you are logged in to (`oc login`, `oc project`).
#   ./scripts/deploy-frontend.sh
# Set NAMESPACE to deploy into another existing project, OVERLAY to use another overlay (default: sandbox).
set -euo pipefail

OVERLAY="${OVERLAY:-sandbox}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[ -d "$ROOT/frontend/openshift/overlays/$OVERLAY" ] || { echo "Unknown overlay: $OVERLAY" >&2; exit 1; }
NAMESPACE="${NAMESPACE:-$(oc project -q)}"
oc project "$NAMESPACE" >/dev/null

oc apply -k "$ROOT/frontend/openshift/overlays/$OVERLAY"

# Build from the latest frontend commit; the Deployment rolls out when the new image lands.
build="$(oc start-build frontend -o name)"
echo "Waiting for $build..."
if ! oc wait "$build" --for=jsonpath='{.status.phase}'=Complete --timeout=20m; then
  oc logs "$build" --tail=50 || true
  echo "$build did not complete" >&2
  exit 1
fi

oc rollout status deployment/frontend --timeout=5m

HOST="$(oc get route frontend -o jsonpath='{.spec.host}')"
echo "Frontend: https://$HOST/"
