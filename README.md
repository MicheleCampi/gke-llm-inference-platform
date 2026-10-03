# gke-llm-inference-platform

[![ci](https://github.com/MicheleCampi/gke-llm-inference-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/MicheleCampi/gke-llm-inference-platform/actions/workflows/ci.yml)

Terraform-to-GitOps LLM inference platform on GKE: a regional cluster with a
scale-to-zero L4 GPU pool, and an ArgoCD app-of-apps that deploys
[vllm-coldstart-operator](https://github.com/MicheleCampi/vllm-coldstart-operator),
external-secrets and a Grafana Alloy pipeline, serving Qwen2.5-7B-Instruct on
the L4. GCP twin of
[eks-llm-inference-platform](https://github.com/MicheleCampi/eks-llm-inference-platform):
the same operator, deployed through an ArgoCD app-of-apps, on a different cloud.

**End to end on a real GPU, 2026-06-14**
([evidence](docs/evidence/e2e-2026-06-14/)): six ArgoCD Applications, all
Healthy and all Synced except `monitoring` (see Limits); the `qwen-7b`
VllmService `Ready`, "1/1 replicas ready and warm"; the vLLM pod on the GPU
pool with 0 restarts; a chat completion served (39 prompt + 33 completion
tokens). Then `terraform destroy`: the versioned Terraform state holds 7
resource instances before it and none after it (09:55 UTC), and a later check
of the project found no cluster or VM left. The debugging that got there
is in [docs/phase3-narrative.md](docs/phase3-narrative.md).

## Architecture

    Terraform (GCS backend)
      ├── VPC + subnet          regional routing, private Google access
      └── modules/gke-gpu       regional GKE cluster, Workload Identity
            ├── system-pool     e2-standard-2, 1 node: ArgoCD, operator, Alloy
            └── gpu-pool        g2-standard-4 + 1 L4, 0..1 nodes, tainted nvidia.com/gpu
    ArgoCD (installed once with Helm, then managing itself)
      root  (argocd/root-app.yaml, wave -2)  ->  argocd/apps/
        ├── argocd                    chart argo-cd 9.5.21        wave -1
        ├── external-secrets          chart 2.6.0                 wave -1
        ├── monitoring                SA, SecretStore, ExternalSecret  wave 0
        ├── vllm-coldstart-operator   v0.2.1, qwen-7b on the L4   wave 0
        └── alloy                     chart 1.10.0 -> Grafana Cloud wave 1

## Design decisions

- **No secrets in git, no service-account keys.** Nodes run with
  `GKE_METADATA`; external-secrets reads GCP Secret Manager as the GCP service
  account `eso-grafana-reader` through Workload Identity, bound to the
  Kubernetes service account `monitoring/eso-grafana`.
  [`monitoring/grafana-secret.yaml`](monitoring/grafana-secret.yaml) holds
  references only; the credentials reach the cluster as a Secret that
  external-secrets creates at runtime.
- **Scale-to-zero GPU pool.** `gpu-pool` runs 0 to 1 nodes in one zone
  (`europe-west4-a`) and carries the taint `nvidia.com/gpu=present:NoSchedule`.
  GKE runs the ExtendedResourceToleration admission controller, so a Pod that
  requests `nvidia.com/gpu` gets the toleration without declaring it
  ([GKE docs](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/gpus)).
- **ArgoCD manages itself** after a one-time Helm install
  ([`argocd/apps/argocd.yaml`](argocd/apps/argocd.yaml)): non-HA, the chart's
  defaults, UI through `kubectl port-forward` only, no public IP.
- **Sync waves order the platform**: ArgoCD and external-secrets first, then the
  secret plumbing and the operator, then Alloy.
- **Engine arguments as quoted strings** in the Application's Helm values:
  `helm --set` would turn `8192` and `0.90` into numbers, and the operator's
  CRD types `extraArgs` as an array of strings.
- **Ephemeral by design**: `deletion_protection = false` so `terraform
  destroy` can delete the cluster; the enabled APIs survive a destroy
  (`disable_on_destroy = false`).
- **Least privilege for nodes and control plane.** Both pools run as a
  dedicated service account holding only
  `roles/container.defaultNodeServiceAccount`, the role GKE documents as the
  minimum for nodes, instead of the Compute Engine default service account.
  The control plane accepts connections only from the cluster's nodes and from
  the CIDRs passed in `authorized_networks` at apply time, none by default, so
  no operator address is kept in the repository. The subnet exports sampled
  VPC flow logs, and the cluster carries resource labels.

## Findings from the real-GPU run

Until this run the operator's CI had only exercised a GPU-less placeholder
(`gpu=0`, a pause image) on kind; it had never started a real vLLM Pod on a
GPU. On GKE, each fix exposed the next assumption
([narrative](docs/phase3-narrative.md)):

1. **RuntimeClass.** The operator hardcoded `runtimeClassName: nvidia`; GKE has
   no such RuntimeClass and the API server rejected the Pod. Fixed in operator
   v0.2.0: the field is optional and unset on GKE.
2. **Invocation.** The model was passed through environment variables the
   vLLM image does not read. Fixed in v0.2.0: an explicit `vllm serve <model>`
   command, plus `extraArgs` for engine tuning.
3. **Dynamic linker.** vLLM failed with `libcuda.so.1: cannot open shared
   object file`: GKE mounts the driver under `/usr/local/nvidia/lib64`, and the
   vLLM image does not look there. Fixed in v0.2.1, which sets
   `LD_LIBRARY_PATH` on GPU Pods.
4. **Rolling update on one GPU.** The new Pod waited for the GPU held by the
   old, crash-looping one; deleting the old Pod freed it.
5. **external-secrets 2.6.0** needs a dedicated service account referenced by
   `serviceAccountRef` in the SecretStore (commit `3265f60`).
6. **CRD drift.** The API server drops three CRD fields the chart declares as
   empty arrays; `ignoreDifferences` targets exactly those paths
   (commit `b1ab78d`).

## Continuous integration

Every push to `main` and every pull request runs
[`ci/install-tools.sh`](ci/install-tools.sh) and then
[`ci/validate.sh`](ci/validate.sh), the same two scripts a reviewer runs
locally:

    bash ci/install-tools.sh && bash ci/validate.sh

No cloud credentials, no Terraform state, no cluster. What it checks:

- **Pinned inputs.** Each tool is downloaded at the version in
  [`ci/tools.lock`](ci/tools.lock) and rejected if its SHA-256 differs. The
  Helm charts are checked against their package hash, and the operator is
  fetched at a fixed commit ([`ci/versions.env`](ci/versions.env)). These pins
  must equal the versions the ArgoCD Applications deploy, or the run fails.
- **Terraform**: `fmt -check`, `init -backend=false -lockfile=readonly`,
  `validate`.
- **IaC misconfigurations**: trivy on the Terraform that git would commit,
  with its checks pinned by OCI digest. Accepted findings are listed in
  [`.trivyignore`](.trivyignore), each with a reason and an expiry date, and
  the run fails if one of them is no longer reported.
- **Manifests**: `kubeconform -strict` against JSON schemas generated from the
  CRDs of the deployed chart versions, keeping only the API versions they
  serve; built-in kinds against `kubernetes-json-schema` at a fixed commit.
- **Operator values**: the Helm values in
  [`argocd/apps/operator.yaml`](argocd/apps/operator.yaml) are rendered with
  the operator's chart, and the `VllmService` that comes out is validated
  against its CRD. A number where the CRD wants a string, the failure
  described under Design decisions, is rejected here instead of by the API
  server.
- **Secrets and workflow**: gitleaks on the full history, actionlint on the
  workflow.

**Self-test.** A check that cannot fail proves nothing, so every run also
feeds in six broken inputs and requires each to be rejected for the reason
named: a number in `extraArgs`, an unknown field in a `VllmService`, a
`SecretStore` at an API version the chart does not serve (`v1beta1`), an
unformatted Terraform file, a cluster without resource labels, and a token in
a file. If one is accepted, or
rejected for another reason, the run fails.

The workflow uses one action, `actions/checkout`, pinned by commit, with
`contents: read` permissions.

## Bootstrap (one-time, out of band)

These resources are created with `gcloud`, outside Terraform, and survive
`terraform destroy`. `PROJECT_ID` is your project; this repository's own value
appears in `terraform/terraform.tfvars`, in the bucket name of
`terraform/versions.tf`, and twice in `monitoring/grafana-secret.yaml`.

    # Terraform state bucket
    gcloud storage buckets create gs://PROJECT_ID-tfstate --project=PROJECT_ID \
      --location=europe-west4 --default-storage-class=STANDARD \
      --uniform-bucket-level-access --public-access-prevention
    gcloud storage buckets update gs://PROJECT_ID-tfstate --versioning

    # Grafana Cloud remote-write credentials, as JSON with url, user, token
    gcloud services enable secretmanager.googleapis.com
    gcloud secrets create grafana-cloud-remote-write \
      --replication-policy="user-managed" --locations="europe-west4"
    printf '%s' '{"url":"...","user":"...","token":"..."}' | \
      gcloud secrets versions add grafana-cloud-remote-write --data-file=-

    # The GCP service account external-secrets runs as
    gcloud iam service-accounts create eso-grafana-reader \
      --display-name="ESO reader for Grafana Cloud secret"
    gcloud secrets add-iam-policy-binding grafana-cloud-remote-write \
      --member="serviceAccount:eso-grafana-reader@PROJECT_ID.iam.gserviceaccount.com" \
      --role="roles/secretmanager.secretAccessor"

## Run it

    # The CIDR that may reach the control plane; it is not kept in the repository
    export TF_VAR_authorized_networks='[{cidr_block="YOUR_IP/32",display_name="operator"}]'
    cd terraform && terraform init && terraform apply && cd ..
    gcloud container clusters get-credentials capstone-inference \
      --region europe-west4 --project PROJECT_ID

    # Workload Identity: the Kubernetes SA monitoring/eso-grafana acts as the GCP SA
    gcloud iam service-accounts add-iam-policy-binding \
      eso-grafana-reader@PROJECT_ID.iam.gserviceaccount.com \
      --role="roles/iam.workloadIdentityUser" \
      --member="serviceAccount:PROJECT_ID.svc.id.goog[monitoring/eso-grafana]"

    # ArgoCD, once; from here on it manages itself
    helm repo add argo https://argoproj.github.io/argo-helm && helm repo update argo
    helm install argocd argo/argo-cd --version 9.5.21 --namespace argocd \
      --create-namespace -f argocd/bootstrap-values.yaml --wait --timeout 10m

    # ArgoCD reads this repository over SSH, with a read-only deploy key
    kubectl create secret generic capstone-repo --namespace argocd \
      --from-literal=type=git \
      --from-literal=url=git@github.com:MicheleCampi/gke-llm-inference-platform.git \
      --from-file=sshPrivateKey=PATH_TO_DEPLOY_KEY
    kubectl label secret capstone-repo -n argocd \
      argocd.argoproj.io/secret-type=repository

    kubectl apply -f argocd/root-app.yaml      # the only manual apply
    cd terraform && terraform destroy          # stop the meter

## Limits

- `monitoring` was OutOfSync while Healthy in the run: the Secret that
  external-secrets creates differs from Git by construction. The
  `ignoreDifferences` fix (commit `e9fd20e`) came after the run and has not
  been applied to a live cluster.
- One GPU node and the default rolling-update strategy: finding 4 can recur.
- Lab profile: non-HA ArgoCD, a single-zone system pool.
- The bootstrap above is outside Terraform.
- Alloy ships the operator's metrics to Grafana Cloud; there are no alerting
  rules or dashboards in this repository.
- The hardening of 2026-10-03 (node service account, control-plane authorized
  networks, explicit `disable-legacy-endpoints`, flow logs, labels) passes
  `terraform validate`, trivy and the CI self-test, but has not been applied
  to a live cluster yet.
- Two trivy findings are accepted until the next live run, both in
  [`.trivyignore`](.trivyignore): no NetworkPolicy enforcement (GCP-0056),
  since enforcement without written policies changes no traffic, and nodes
  that are not private (GCP-0059), since private nodes need Cloud NAT to pull
  the vLLM image and the model weights.

## License

Apache-2.0
