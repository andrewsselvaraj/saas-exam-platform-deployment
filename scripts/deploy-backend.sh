#!/usr/bin/env bash
# Deploys the backend microservices to the OpenShift project you are logged in to (`oc login`, `oc project`).
#   ./scripts/deploy-backend.sh                  H2 databases on volumes (overlays/sandbox)
#   OVERLAY=mysql ./scripts/deploy-backend.sh    existing m2its MySQL database (overlays/mysql)
# Set NAMESPACE to deploy into another existing project.
set -euo pipefail

OVERLAY="${OVERLAY:-sandbox}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVICES=(catalog-service question-service exam-service api-gateway)
DB_SERVICES=(catalog-service question-service exam-service)

[ -d "$ROOT/backend/openshift/overlays/$OVERLAY" ] || { echo "Unknown overlay: $OVERLAY" >&2; exit 1; }
NAMESPACE="${NAMESPACE:-$(oc project -q)}"
oc project "$NAMESPACE" >/dev/null

# Database credentials, one secret per service that owns a database: generated once,
# never committed. H2 creates each database with them on first start.
for svc in "${DB_SERVICES[@]}"; do
  if ! oc get secret "$svc-db" >/dev/null 2>&1; then
    if [ "$OVERLAY" = mysql ]; then
      # Generated credentials only work for H2, which creates the database with them.
      echo "Secret $svc-db is missing. Create it with the MySQL login for m2its:" >&2
      echo "  oc create secret generic $svc-db --from-literal=SPRING_DATASOURCE_USERNAME=<user> --from-literal=SPRING_DATASOURCE_PASSWORD=<password>" >&2
      exit 1
    fi
    oc create secret generic "$svc-db" \
      --from-literal=SPRING_DATASOURCE_USERNAME="${svc%-service}admin" \
      --from-literal=SPRING_DATASOURCE_PASSWORD="$(openssl rand -base64 24)"
    oc label secret "$svc-db" app.kubernetes.io/name="$svc" app.kubernetes.io/part-of=saas-exam-platform
  fi
done

oc apply -k "$ROOT/backend/openshift/overlays/$OVERLAY"

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
