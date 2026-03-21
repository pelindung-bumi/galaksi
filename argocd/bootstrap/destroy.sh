#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ARGO_NAMESPACE="argo"

read -r -p "This will force delete Argo CD and all related workloads. Continue? [y/N] " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  printf 'Cancelled.\n'
  exit 0
fi

have_command() {
  command -v "$1" >/dev/null 2>&1
}

have_resource() {
  kubectl api-resources --api-group="$2" -o name 2>/dev/null | grep -qx "$1"
}

patch_finalizers() {
  local resource="$1"
  kubectl patch "$resource" --type=merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
}

finalize_namespace() {
  local namespace="$1"

  kubectl get namespace "$namespace" >/dev/null 2>&1 || return 0

  printf 'Finalizing namespace/%s...\n' "$namespace"
  kubectl patch namespace "$namespace" --type=merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true

  if have_command jq; then
    kubectl get namespace "$namespace" -o json 2>/dev/null \
      | jq '.spec.finalizers=[]' \
      | kubectl replace --raw "/api/v1/namespaces/${namespace}/finalize" -f - >/dev/null 2>&1 || true
  fi
}

delete_argocd_kind() {
  local kind="$1"

  have_resource "$kind" argoproj.io || return 0

  mapfile -t names < <(kubectl get "$kind" -n "$ARGO_NAMESPACE" -o name 2>/dev/null || true)

  if ((${#names[@]} == 0)); then
    return 0
  fi

  printf 'Removing finalizers from %s...\n' "$kind"
  for name in "${names[@]}"; do
    patch_finalizers "$name"
  done

  printf 'Deleting %s...\n' "$kind"
  kubectl delete "$kind" --all -n "$ARGO_NAMESPACE" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

delete_namespaced_resources_in() {
  local namespace="$1"

  printf 'Removing namespaced resources in %s...\n' "$namespace"

  while read -r resource; do
    [[ -z "$resource" ]] && continue
    kubectl get "$resource" -n "$namespace" -o name 2>/dev/null | while read -r name; do
      [[ -z "$name" ]] && continue
      patch_finalizers "$name"
    done
    kubectl delete "$resource" --all -n "$namespace" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  done < <(kubectl api-resources --verbs=list --namespaced -o name 2>/dev/null)

  kubectl delete pod --all -n "$namespace" --ignore-not-found --force --grace-period=0 >/dev/null 2>&1 || true
}

delete_cr_instances() {
  local pattern="$1"

  while read -r resource; do
    [[ -z "$resource" ]] && continue
    kubectl get "$resource" -A -o name 2>/dev/null | while read -r name; do
      [[ -z "$name" ]] && continue
      patch_finalizers "$name"
    done
    kubectl delete "$resource" --all -A --ignore-not-found --wait=false >/dev/null 2>&1 || true
  done < <(kubectl api-resources --verbs=list --namespaced -o name 2>/dev/null | grep -E "$pattern" || true)
}

delete_crds_by_pattern() {
  local pattern="$1"
  mapfile -t crds < <(kubectl get crd -o name 2>/dev/null | grep -E "$pattern" || true)

  if ((${#crds[@]} == 0)); then
    return 0
  fi

  printf 'Removing finalizers from matching CRDs...\n'
  for crd in "${crds[@]}"; do
    patch_finalizers "$crd"
  done

  printf 'Deleting CRDs matching pattern: %s\n' "$pattern"
  kubectl delete "${crds[@]}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

printf 'Deleting Argo CD custom resources...\n'
delete_argocd_kind applicationsets
delete_argocd_kind applications
delete_argocd_kind appprojects

printf 'Deleting gateway, envoy, rook, and ceph custom resources...\n'
delete_cr_instances 'gateway\.networking\.k8s\.io|gateway\.envoyproxy\.io|ceph\.rook\.io|csi\.ceph\.io'

printf 'Deleting known cluster-scoped resources...\n'
kubectl delete gatewayclass --all --ignore-not-found --wait=false >/dev/null 2>&1 || true
kubectl delete storageclass rook-ceph-block --ignore-not-found --wait=false >/dev/null 2>&1 || true

printf 'Removing Argo CD Helm release...\n'
helm uninstall argocd -n "$ARGO_NAMESPACE" >/dev/null 2>&1 || true

for namespace in argo rook-ceph cert-manager envoy-gateway-system pelindung-bumi observability; do
  delete_namespaced_resources_in "$namespace"
done

printf 'Deleting known namespaces...\n'
kubectl delete namespace argo rook-ceph cert-manager envoy-gateway-system pelindung-bumi observability --ignore-not-found --wait=false >/dev/null 2>&1 || true

for namespace in argo rook-ceph cert-manager envoy-gateway-system pelindung-bumi observability; do
  finalize_namespace "$namespace"
done

printf 'Deleting Argo CD CRDs...\n'
delete_crds_by_pattern 'applications\.argoproj\.io|applicationsets\.argoproj\.io|appprojects\.argoproj\.io|argocdextensions\.argoproj\.io'

printf 'Deleting gateway, envoy, rook, and ceph CRDs...\n'
delete_crds_by_pattern 'gateway\.networking\.k8s\.io|gateway\.envoyproxy\.io|ceph\.rook\.io|csi\.ceph\.io'

for namespace in argo rook-ceph cert-manager envoy-gateway-system pelindung-bumi observability; do
  finalize_namespace "$namespace"
done

printf 'Destroy completed. Verify cluster is empty before rerunning bootstrap.\n'
