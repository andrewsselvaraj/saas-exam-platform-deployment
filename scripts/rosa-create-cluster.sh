#!/usr/bin/env bash
# Creates a ROSA (Red Hat OpenShift Service on AWS) classic cluster with STS.
# Prerequisites: aws CLI configured for the target account, rosa CLI, and
# `rosa login` done with a token from https://console.redhat.com/openshift/token.
# ROSA must be enabled once per AWS account in the AWS console (Red Hat OpenShift service page).
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-saas-exam}"
AWS_REGION="${AWS_REGION:-ap-south-1}"
COMPUTE_MACHINE_TYPE="${COMPUTE_MACHINE_TYPE:-m5.xlarge}"
REPLICAS="${REPLICAS:-2}"

rosa verify quota --region "$AWS_REGION"
rosa verify permissions --region "$AWS_REGION"

# Account-wide IAM roles (idempotent) and the cluster with operator roles / OIDC created automatically.
rosa create account-roles --mode auto --yes
rosa create cluster \
  --cluster-name "$CLUSTER_NAME" \
  --sts --mode auto --yes \
  --region "$AWS_REGION" \
  --compute-machine-type "$COMPUTE_MACHINE_TYPE" \
  --replicas "$REPLICAS"

echo "Waiting for the cluster to become ready (this takes a while)..."
rosa logs install --cluster "$CLUSTER_NAME" --watch

# Temporary cluster-admin user; replace with an identity provider (GitHub, OIDC) for real use.
rosa create admin --cluster "$CLUSTER_NAME"
echo "Log in with the 'oc login' command printed above, then run scripts/deploy-backend.sh."
