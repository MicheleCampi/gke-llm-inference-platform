#!/usr/bin/env bash
# Point root at a signed tag. root is pinned to a tag, so it cannot read its
# own next pin: every new tag (D-0095) needs this step. --check: verify only.
set -euo pipefail
cd "$(dirname "$0")/.."
C=0; [ "${1:-}" = "--check" ] && { C=1; shift; }
T=${1:?usage: promote-tag.sh [--check] vX.Y.Z}
git fetch -q --tags origin main
git tag -v "$T" >/dev/null 2>&1 || { echo "tag $T missing or signature not verified" >&2; exit 1; }
git merge-base --is-ancestor "$T" origin/main || { echo "tag $T is not on origin/main" >&2; exit 1; }
M=$(git show "$T:argocd/root-app.yaml")
grep -qE "^\s*targetRevision: $T\s*$" <<<"$M" || { echo "root-app.yaml at $T does not pin $T" >&2; exit 1; }
echo "ok: $T signed, on main, root-app pins it"
[ "$C" = 1 ] && exit 0
kubectl apply -f - <<<"$M"
kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite >/dev/null
kubectl -n argocd get application root -o jsonpath='{.spec.source.targetRevision} {.status.sync.status}{"\n"}'
