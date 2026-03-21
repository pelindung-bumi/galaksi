#!/usr/bin/env bash

set -euo pipefail

read -r -p "This will delete Argo CD and workloads managed from namespace 'argo'. Continue? [y/N] " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  printf 'Cancelled.\n'
  exit 0
fi

printf 'Deleting Argo CD managed applications...\n'
kubectl delete applications.argoproj.io --all -n argo --ignore-not-found --wait=false
kubectl delete applicationsets.argoproj.io --all -n argo --ignore-not-found --wait=false
kubectl delete appprojects.argoproj.io --all -n argo --ignore-not-found --wait=false

printf 'Deleting common managed namespaces...\n'
kubectl delete namespace cert-manager envoy-gateway-system pelindung-bumi observability rook-ceph --ignore-not-found --wait=false

printf 'Removing Argo CD release and namespace...\n'
helm uninstall argocd -n argo || true
kubectl delete namespace argo --ignore-not-found --wait=false

printf 'Removing Argo CD CRDs...\n'
kubectl delete crd applications.argoproj.io appprojects.argoproj.io applicationsets.argoproj.io --ignore-not-found
kubectl delete crd argocdextensions.argoproj.io --ignore-not-found

printf 'Cleanup requested. Some namespace deletions may continue in background.\n'
