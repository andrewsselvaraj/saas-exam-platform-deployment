#!/usr/bin/env bash
# Deploys the backend to the OpenShift cluster you are logged in to with `oc login`.
set -euo pipefail

NAMESPACE="${NAMESPACE:-saas-exam}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

oc get project "$NAMESPACE" >/dev/null 2>&1 || oc new-project "$NAMESPACE" >/dev/null
oc project "$NAMESPACE" >/dev/null

# Database credentials: generated once, never committed. H2 creates the DB with them on first start.
if ! oc get secret exam-backend-db >/dev/null 2>&1; then
  oc create secret generic exam-backend-db \
    --from-literal=SPRING_DATASOURCE_USERNAME=examadmin \
    --from-literal=SPRING_DATASOURCE_PASSWORD="$(openssl rand -base64 24)"
  oc label secret exam-backend-db app.kubernetes.io/name=exam-backend
fi

oc apply -k "$ROOT/backend/openshift/overlays/rosa"

# Build the latest backend commit; the Deployment rolls out when the new image lands.
oc start-build exam-backend --follow

oc rollout status deployment/exam-backend --timeout=10m

HOST="$(oc get route exam-backend -o jsonpath='{.spec.host}')"
echo "API:        https://$HOST/api/orgs"
echo "Swagger UI: https://$HOST/swagger-ui.html"
