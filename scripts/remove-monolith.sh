#!/usr/bin/env bash
# Removes the old single-backend deployment (exam-backend) after the microservices are up.
# This deletes the monolith's H2 data volume; the microservices seed their own databases.
set -euo pipefail

NAMESPACE="${NAMESPACE:-saas-exam}"
oc project "$NAMESPACE" >/dev/null

read -r -p "Delete exam-backend and its data volume in $NAMESPACE? [y/N] " answer
[ "$answer" = "y" ] || { echo "Nothing deleted."; exit 0; }

oc delete route,service,deployment,buildconfig,imagestream,configmap,secret,pvc \
  -l app.kubernetes.io/name=exam-backend --ignore-not-found
