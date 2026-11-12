#!/usr/bin/env bash
# Bootstrap ArgoCD once, then the root app; from there ArgoCD manages itself.
# The chart version is read from argocd/apps/argocd.yaml, the one ArgoCD then
# keeps in sync. helm pull retries: the chart sits on GitHub's release CDN,
# which returned 503s in the B-008 drill. Needs helm and kubectl on a context
# that points at the new cluster.
set -euo pipefail
cd "$(dirname "$0")/.."
V=$(awk '/chart: argo-cd/{getline; print $2}' argocd/apps/argocd.yaml)
[ -n "$V" ] || { echo "argo-cd chart version not found in argocd/apps/argocd.yaml" >&2; exit 1; }
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
n=1; d=15
until helm pull argo-cd --repo https://argoproj.github.io/argo-helm --version "$V" -d "$D"; do
  [ "$n" -ge 5 ] && { echo "helm pull failed 5 times" >&2; exit 1; }
  echo "helm pull retry $n/4 in ${d}s" >&2; sleep "$d"; n=$((n+1)); d=$((d*2))
done
helm install argocd "$D/argo-cd-$V.tgz" --namespace argocd --create-namespace \
  -f argocd/bootstrap-values.yaml --wait --timeout 10m
kubectl apply -f argocd/root-app.yaml
echo "after every new tag: scripts/promote-tag.sh vX.Y.Z (root does not follow tags by itself)"
