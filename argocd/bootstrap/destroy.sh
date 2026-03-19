#!/usr/bin/env bash

# NOTES: HATI-HATI JALANIN INI GUYS! BAKAL DELETE SEMUANYA INI, INI DIPAKAI CUMA KALAU BENAR-BENAR BUTUH CLEANUP

kubectl delete application root -n argo --ignore-not-found --force --grace-period=0
kubectl delete application argo-system -n argo --ignore-not-found --force --grace-period=0
helm uninstall argocd -n argo || true
kubectl delete namespace argo --ignore-not-found --force --grace-period=0
kubectl delete crd applications.argoproj.io appprojects.argoproj.io applicationsets.argoproj.io --ignore-not-found
kubectl delete crd argocdextensions.argoproj.io --ignore-not-found
