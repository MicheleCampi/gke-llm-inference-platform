#!/usr/bin/env bash
# Static validation of the platform, run identically in CI and locally:
#   bash ci/install-tools.sh && bash ci/validate.sh
# No cloud credentials, no Terraform state, no cluster.
#
# Part 1 checks the repository. Part 2 is a self-test: each negative case
# must be rejected, and for the reason named, or the run fails. A check that
# cannot fail proves nothing.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
CI_BIN=${CI_BIN:-$ROOT/.ci-bin}
export PATH="$CI_BIN:$CI_BIN/venv/bin:$PATH"
. ci/versions.env
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fail=0
. ci/platform-ci.env
# The helpers (pass, check, expect_reject, same, tag_is) and the Kubernetes
# schema pins come from inference-platform-ci, installed by
# ci/install-tools.sh. Without them every check would be undefined and fail
# would stay 0, so a missing file stops the run here instead of letting it
# report success.
for f in lib.sh versions.env; do
  . "$CI_BIN/platform-ci/$f" || { echo "no $CI_BIN/platform-ci/$f: run bash ci/install-tools.sh first" >&2; exit 1; }
done

echo "== shared CI files at the commit pinned in ci/platform-ci.env"
same platform-ci-commit "$(git -C "$CI_BIN/platform-ci" rev-parse HEAD)" "$PLATFORM_CI_COMMIT"

echo "== pins match what ArgoCD deploys"
same pin-argocd-chart   "$(yq '.spec.sources[0].targetRevision' argocd/apps/argocd.yaml)"         "$ARGOCD_CHART_VERSION"
same pin-eso-chart      "$(yq '.spec.source.targetRevision' argocd/apps/external-secrets.yaml)"   "$ESO_CHART_VERSION"
same pin-operator       "$(yq '.spec.source.targetRevision' argocd/apps/operator.yaml)"           "$OPERATOR_TAG"

echo "== terraform"
check tf-fmt      sh -c "terraform -chdir=terraform fmt -check -recursive -diff && terraform -chdir=bootstrap fmt -check -recursive -diff"
check tf-init     terraform -chdir=terraform init -backend=false -lockfile=readonly -input=false -no-color
check tf-validate terraform -chdir=terraform validate -no-color
check bootstrap-init     terraform -chdir=bootstrap/ci-identity init -backend=false -lockfile=readonly -input=false -no-color
check bootstrap-validate terraform -chdir=bootstrap/ci-identity validate -no-color

echo "== IaC misconfigurations (trivy; checks pinned by digest, exceptions in .trivyignore)"
TRIVY=(trivy config --quiet --cache-dir "$W/trivy-cache" --checks-bundle-repository "$TRIVY_CHECKS")
trivy_fail_ids() { # dir -> sorted IDs of failed checks, with no ignore file
  "${TRIVY[@]}" --ignorefile "" --format json -o "$W/trivy-ids.json" "$1" >/dev/null 2>&1 &&
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(" ".join(sorted({m["ID"] for r in d.get("Results") or [] for m in r.get("Misconfigurations") or [] if m["Status"] == "FAIL"})))' "$W/trivy-ids.json"
}
# Scan exactly what git would commit: tracked files plus new ones not ignored.
# A working tree can hold ignored files, such as a saved plan, whose config
# snapshot trivy would scan as well.
IAC="$W/iac"; mkdir -p "$IAC" && git ls-files -co --exclude-standard terraform bootstrap | tar -cf - -T - | tar -xf - -C "$IAC"
check trivy "${TRIVY[@]}" --exit-code 1 --ignorefile .trivyignore "$IAC"
# An exception that is no longer needed fails the run instead of lingering.
same trivy-exceptions-still-needed "$(trivy_fail_ids "$IAC")" "$(grep -o -E '^[A-Z]+-[0-9]+' .trivyignore | sort -u | paste -sd' ')"

echo "== schemas from the CRDs of the deployed versions (served versions only)"
cat > "$W/served.py" <<'PY'
import sys, yaml
out = []
for d in yaml.safe_load_all(sys.stdin):
    if d and d.get("kind") == "CustomResourceDefinition" and d["metadata"]["name"] in sys.argv[1:]:
        d["spec"]["versions"] = [v for v in d["spec"]["versions"] if v.get("served")]
        out.append(d)
assert len(out) == len(sys.argv[1:]), f"found {len(out)} of {len(sys.argv[1:])} CRDs"
yaml.safe_dump_all(out, sys.stdout)
PY
pull() { # name repo version sha256
  helm pull "$1" --repo "$2" --version "$3" -d "$W" >/dev/null &&
  [ "$(sha256sum "$W/$1-$3.tgz" | cut -d' ' -f1)" = "$4" ]
}
check chart-argocd pull argo-cd https://argoproj.github.io/argo-helm "$ARGOCD_CHART_VERSION" "$ARGOCD_CHART_SHA256"
check chart-eso    pull external-secrets https://charts.external-secrets.io "$ESO_CHART_VERSION" "$ESO_CHART_SHA256"
# Fetch the operator at the tag ArgoCD deploys, then require the tag to
# resolve to the pinned commit: a moved or re-pointed tag fails the run.
check operator-src sh -c "git init -q '$W/op' && git -C '$W/op' fetch -q --depth 1 https://github.com/MicheleCampi/vllm-coldstart-operator.git 'refs/tags/$OPERATOR_TAG:refs/tags/$OPERATOR_TAG' && git -C '$W/op' checkout -q 'refs/tags/$OPERATOR_TAG'"
check operator-tag-commit tag_is "$W/op" "$OPERATOR_TAG" "$OPERATOR_COMMIT"
helm template argocd "$W/argo-cd-$ARGOCD_CHART_VERSION.tgz" 2>/dev/null | python3 "$W/served.py" applications.argoproj.io > "$W/crd-argo.yaml"
helm template eso "$W/external-secrets-$ESO_CHART_VERSION.tgz" 2>/dev/null | python3 "$W/served.py" secretstores.external-secrets.io externalsecrets.external-secrets.io > "$W/crd-eso.yaml"
python3 "$W/served.py" vllmservices.inference.michelecampi.dev < "$W/op/chart/crds/crd.yaml" > "$W/crd-op.yaml"
for g in argoproj.io:argo external-secrets.io:eso inference.michelecampi.dev:op; do
  mkdir -p "$W/schemas/${g%%:*}" && (cd "$W/schemas/${g%%:*}" && python3 "$CI_BIN/openapi2jsonschema.py" "$W/crd-${g##*:}.yaml" >/dev/null)
done
(cd "$W/schemas" && find . -name '*.json' | sort | sed 's/^/  /')
KC=(kubeconform -strict -summary -kubernetes-version "$K8S_SCHEMA_VERSION"
    -schema-location "https://raw.githubusercontent.com/yannh/kubernetes-json-schema/$K8S_SCHEMA_COMMIT/{{.NormalizedKubernetesVersion}}-standalone{{.StrictSuffix}}/{{.ResourceKind}}{{.KindSuffix}}.json"
    -schema-location "$W/schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json")

echo "== manifests"
check manifests "${KC[@]}" argocd/root-app.yaml argocd/apps/*.yaml monitoring/*.yaml
grep -h Summary "$W/manifests.log" | sed 's/^/  /'

echo "== operator values, rendered with the operator chart"
yq '.spec.source.helm.values' argocd/apps/operator.yaml > "$W/op-values.yaml"
check operator-render sh -c "helm template vllm-coldstart-operator '$W/op/chart' -f '$W/op-values.yaml' > '$W/op-render.yaml'"
check operator-values "${KC[@]}" "$W/op-render.yaml"
grep -h Summary "$W/operator-values.log" | sed 's/^/  /'

echo "== secrets in the full history"
check gitleaks gitleaks git --redact --no-banner .

echo "== workflows"
check actionlint actionlint

echo "== self-test: each case must be rejected for the reason named"
yq '.example.spec.extraArgs[1] = 8192' "$W/op-values.yaml" > "$W/neg-values.yaml"
helm template x "$W/op/chart" -f "$W/neg-values.yaml" > "$W/neg-values-render.yaml"
expect_reject neg-number-in-helm-values "extraArgs/1': got number, want string" "${KC[@]}" "$W/neg-values-render.yaml"
yq 'select(.kind=="VllmService") | .spec.gpuz = 1' "$W/op-render.yaml" > "$W/neg-unknown.yaml"
expect_reject neg-unknown-field "additional properties 'gpuz' not allowed" "${KC[@]}" "$W/neg-unknown.yaml"
yq '(select(.kind=="SecretStore") | .apiVersion) = "external-secrets.io/v1beta1"' monitoring/grafana-secret.yaml > "$W/neg-v1beta1.yaml"
expect_reject neg-unserved-api-version "could not find schema for SecretStore" "${KC[@]}" "$W/neg-v1beta1.yaml"
cp -r terraform "$W/tf" && sed -i 's/^  default     = "us-central1"$/  default = "us-central1"/' "$W/tf/variables.tf"
expect_reject neg-terraform-format "variables.tf" terraform -chdir="$W/tf" fmt -check -recursive
cp -r "$IAC/terraform" "$W/tf-nolabels" && sed -i '/^  resource_labels = var.resource_labels$/d' "$W/tf-nolabels/modules/gke-gpu/main.tf"
expect_reject neg-iac-misconfiguration "GCP-0051" "${TRIVY[@]}" --exit-code 1 --ignorefile .trivyignore "$W/tf-nolabels"
mkdir -p "$W/leak" && printf 'token = "ghp_%s"\n' "$(head -c 300 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 36)" > "$W/leak/config.txt"
expect_reject neg-secret "leaks found: 1" gitleaks dir --redact --no-banner "$W/leak"
expect_reject neg-tag-not-pinned-commit "resolves to $OPERATOR_COMMIT, not the pinned" tag_is "$W/op" "$OPERATOR_TAG" 0000000000000000000000000000000000000000

echo; if [ "$fail" = 0 ]; then echo "RESULT: all checks passed"; else echo "RESULT: failed"; fi
exit "$fail"
