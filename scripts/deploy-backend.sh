#!/usr/bin/env bash
# Deploys the backend microservices to the OpenShift cluster you are logged in to with `oc login`.
set -euo pipefail

NAMESPACE="${NAMESPACE:-saas-exam}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVICES=(catalog-service question-service exam-service api-gateway)
DB_SERVICES=(catalog-service question-service exam-service)

oc get project "$NAMESPACE" >/dev/null 2>&1 || oc new-project "$NAMESPACE" >/dev/null
oc project "$NAMESPACE" >/dev/null

# Database credentials, one secret per service that owns a database: generated once,
# never committed. H2 creates each database with them on first start.
for svc in "${DB_SERVICES[@]}"; do
  if ! oc get secret "$svc-db" >/dev/null 2>&1; then
    oc create secret generic "$svc-db" \
      --from-literal=SPRING_DATASOURCE_USERNAME="${svc%-service}admin" \
      --from-literal=SPRING_DATASOURCE_PASSWORD="$(openssl rand -base64 24)"
    oc label secret "$svc-db" app.kubernetes.io/name="$svc" app.kubernetes.io/part-of=saas-exam-platform
  fi
done

oc apply -k "$ROOT/backend/openshift/overlays/rosa"

# Build every service from the latest backend commit in parallel; each Deployment
# rolls out when its new image lands.
builds=()
for svc in "${SERVICES[@]}"; do
  builds+=("$(oc start-build "$svc" -o name)")
done
for build in "${builds[@]}"; do
  echo "Waiting for $build..."
  if ! oc wait "$build" --for=jsonpath='{.status.phase}'=Complete --timeout=20m; then
    oc logs "$build" --tail=50 || true
    echo "$build did not complete" >&2
    exit 1
  fi
done

for svc in "${SERVICES[@]}"; do
  oc rollout status "deployment/$svc" --timeout=10m
done

HOST="$(oc get route api-gateway -o jsonpath='{.spec.host}')"
echo "API (through the gateway): https://$HOST/api/orgs"
