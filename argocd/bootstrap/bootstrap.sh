#!/usr/bin/env bash

set -euo pipefail

ARGOCD_CHART_VERSION=9.4.15
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

kubectl apply -f "$SCRIPT_DIR/namespace.yaml"

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm template argocd argo/argo-cd -n argo --version "$ARGOCD_CHART_VERSION" | kubectl apply --server-side -f -

kubectl wait --for=condition=Established --timeout=120s crd/appprojects.argoproj.io
kubectl wait --for=condition=Established --timeout=120s crd/applications.argoproj.io
kubectl wait --for=condition=Available --timeout=180s deployment/argocd-server -n argo

for _ in $(seq 1 60); do
  if kubectl get appproject default -n argo >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

kubectl get appproject default -n argo >/dev/null 2>&1

kubectl apply -f "$SCRIPT_DIR/secret.yaml"
kubectl apply -f "$SCRIPT_DIR/app.yaml"
