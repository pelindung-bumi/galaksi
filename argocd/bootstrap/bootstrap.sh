#!/usr/bin/env bash

set -euo pipefail

ARGOCD_CHART_VERSION=9.4.15

kubectl apply -f namespace.yaml

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm template argocd argo/argo-cd -n argo --version "$ARGOCD_CHART_VERSION" | kubectl apply --server-side -f -

kubectl apply -f secret.yaml
kubectl apply -f app.yaml
