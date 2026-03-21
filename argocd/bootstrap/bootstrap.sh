#!/usr/bin/env bash

set -euo pipefail

ARGOCD_CHART_VERSION=9.4.15
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

kubectl apply -f "$SCRIPT_DIR/namespace.yaml"

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm template argocd argo/argo-cd -n argo --version "$ARGOCD_CHART_VERSION" | kubectl apply --server-side -f -

kubectl apply -f "$SCRIPT_DIR/secret.yaml"
kubectl apply -f "$SCRIPT_DIR/app.yaml"
