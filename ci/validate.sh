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
pass() { echo "PASS $1"; }
check() { local n=$1; shift; if "$@" >"$W/$n.log" 2>&1; then pass "$n"; else echo "FAIL $n"; tail -20 "$W/$n.log"; fail=1; fi; }
expect_reject() {
  local n=$1 reason=$2; shift 2
  if "$@" >"$W/$n.log" 2>&1; then echo "FAIL $n: accepted, should have been rejected"; fail=1
  elif grep -q -E "$reason" "$W/$n.log"; then echo "PASS $n: rejected ($(grep -m1 -o -E ".{0,40}$reason.{0,40}" "$W/$n.log"))"
  else echo "FAIL $n: rejected for another reason"; tail -5 "$W/$n.log"; fail=1; fi
}
same() { if [ "$2" = "$3" ]; then pass "$1 ($2)"; else echo "FAIL $1: $2 != $3"; fail=1; fi; }

echo "== pins match what ArgoCD deploys"
same pin-argocd-chart   "$(yq '.spec.sources[0].targetRevision' argocd/apps/argocd.yaml)"         "$ARGOCD_CHART_VERSION"
same pin-eso-chart      "$(yq '.spec.source.targetRevision' argocd/apps/external-secrets.yaml)"   "$ESO_CHART_VERSION"
same pin-operator       "$(yq '.spec.source.targetRevision' argocd/apps/operator.yaml)"           "$OPERATOR_TAG"

echo "== terraform"
check tf-fmt      terraform -chdir=terraform fmt -check -recursive -diff
check tf-init     terraform -chdir=terraform init -backend=false -lockfile=readonly -input=false -no-color
check tf-validate terraform -chdir=terraform validate -no-color

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
check operator-src sh -c "git init -q '$W/op' && git -C '$W/op' fetch -q --depth 1 https://github.com/MicheleCampi/vllm-coldstart-operator.git '$OPERATOR_COMMIT' && git -C '$W/op' checkout -q FETCH_HEAD && [ \"\$(git -C '$W/op' rev-parse HEAD)\" = '$OPERATOR_COMMIT' ]"
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
cp -r terraform "$W/tf" && sed -i 's/^  default     = "europe-west4"$/  default = "europe-west4"/' "$W/tf/variables.tf"
expect_reject neg-terraform-format "variables.tf" terraform -chdir="$W/tf" fmt -check -recursive
mkdir -p "$W/leak" && printf 'token = "ghp_%s"\n' "$(head -c 300 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 36)" > "$W/leak/config.txt"
expect_reject neg-secret "leaks found: 1" gitleaks dir --redact --no-banner "$W/leak"

echo; if [ "$fail" = 0 ]; then echo "RESULT: all checks passed"; else echo "RESULT: failed"; fi
exit "$fail"
