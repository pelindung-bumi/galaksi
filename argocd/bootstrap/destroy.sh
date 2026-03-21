#!/usr/bin/env bash

set -euo pipefail

ARGO_NAMESPACE="argo"

read -r -p "This will delete Argo CD and workloads managed from namespace '${ARGO_NAMESPACE}'. Continue? [y/N] " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  printf 'Cancelled.\n'
  exit 0
fi

have_resource() {
  kubectl api-resources --api-group=argoproj.io -o name 2>/dev/null | grep -qx "$1"
}

clear_namespace_finalizers() {
  local namespace="$1"

  if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
    return 0
  fi

  printf 'Removing finalizers from namespace/%s...\n' "$namespace"
  kubectl patch namespace "$namespace" --type=merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
  kubectl get namespace "$namespace" -o json 2>/dev/null \
    | jq '.spec.finalizers=[]' \
    | kubectl replace --raw "/api/v1/namespaces/${namespace}/finalize" -f - >/dev/null 2>&1 || true
}

delete_argocd_objects() {
  local kind="$1"

  if ! have_resource "$kind"; then
    return 0
  fi

  mapfile -t names < <(kubectl get "$kind" -n "$ARGO_NAMESPACE" -o name 2>/dev/null || true)

  if ((${#names[@]} == 0)); then
    return 0
  fi

  printf 'Removing finalizers from %s...\n' "$kind"
  for name in "${names[@]}"; do
    kubectl patch -n "$ARGO_NAMESPACE" "$name" --type=merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
  done

  printf 'Deleting %s...\n' "$kind"
  kubectl delete "$kind" --all -n "$ARGO_NAMESPACE" --ignore-not-found --wait=false || true
}

collect_managed_namespaces() {
  if ! have_resource "applications"; then
    return 0
  fi

  kubectl get applications.argoproj.io -n "$ARGO_NAMESPACE" -o jsonpath='{range .items[*]}{.spec.destination.namespace}{"\n"}{end}' 2>/dev/null \
    | grep -v '^$' \
    | grep -v "^${ARGO_NAMESPACE}$" \
    | sort -u || true
}

printf 'Collecting managed namespaces from Argo CD applications...\n'
mapfile -t managed_namespaces < <(collect_managed_namespaces)

delete_argocd_objects "applicationsets"
delete_argocd_objects "applications"
delete_argocd_objects "appprojects"

if ((${#managed_namespaces[@]} > 0)); then
  printf 'Deleting managed namespaces...\n'
  kubectl delete namespace "${managed_namespaces[@]}" --ignore-not-found --wait=false || true
  for namespace in "${managed_namespaces[@]}"; do
    clear_namespace_finalizers "$namespace"
  done
fi

printf 'Removing Argo CD release and namespace...\n'
helm uninstall argocd -n "$ARGO_NAMESPACE" || true
kubectl delete namespace "$ARGO_NAMESPACE" --ignore-not-found --wait=false || true
clear_namespace_finalizers "$ARGO_NAMESPACE"

printf 'Removing Argo CD CRDs...\n'
kubectl delete crd applications.argoproj.io appprojects.argoproj.io applicationsets.argoproj.io argocdextensions.argoproj.io --ignore-not-found || true

printf 'Cleanup requested. Namespace deletions may continue in background.\n'
