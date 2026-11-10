# Upgrade and disaster recovery

What the platform does today, and what it does not do yet.

## Kubernetes upgrades

- Regional cluster (`location = var.region`, default `us-central1`): the control plane is replicated across zones, so a control-plane upgrade does not take the API down.
- Enrolled in a GKE release channel (`var.release_channel`, default `REGULAR`): Google rolls minor and patch versions; we do not pin a GKE version by hand.
- Both node pools have `auto_upgrade = true` and `auto_repair = true`.
- Not yet: no maintenance window or exclusion, so upgrades can land at any time; no explicit surge or blue-green upgrade settings, so the GKE defaults apply. For a serving workload, the next steps are a maintenance window outside peak hours and PodDisruptionBudgets on the inference pods.

## Platform component upgrades

- Everything Argo CD deploys is pinned: Helm charts to an exact version, this repo to a release tag (`targetRevision`).
- An upgrade is a pull request that moves a pin; CI validates it (lint, trivy, tenancy check) before merge.
- Rollback is the same pull request reverted: Argo CD syncs back to the previous pin.
- Changes merged to `main` reach the cluster only when a new tag is cut and the pins move to it.

## Disaster recovery

| Asset | Where it lives | Recovery |
|---|---|---|
| Infrastructure | Terraform in this repo | `terraform apply` (from CI, plan saved and approved) |
| Terraform state | GCS bucket, versioning on, 7-day soft delete, `EUROPE-WEST4` | restore a previous object version |
| Cluster workloads | Git, through Argo CD | bootstrap Argo CD, apply `root-app.yaml`; everything else syncs |
| Secrets | Google Secret Manager, read by External Secrets | survive a cluster loss; nothing to restore |
| CI identity | `bootstrap/ci-identity`, own state | outside the cluster lifecycle |

- The cluster is cattle: it is destroyed after every working session and rebuilt from Git, so the rebuild path is exercised, not theoretical.
- `deletion_protection = false` is deliberate, for that destroy-and-rebuild cycle. A production cluster would set it to `true`.
- The workloads are stateless (model weights are pulled at start), so there is no in-cluster data to back up.

## Drill, 9 November 2026

One timed rebuild, from no cluster to a model answering, with apply from CI
([run 42682889956](https://github.com/MicheleCampi/gke-llm-inference-platform/actions/runs/42682889956)).

| Step | Time (UTC) |
|---|---|
| T0: `apply.yml` dispatched, no cluster | 19:23:32 |
| Terraform apply finished | 19:41:44 |
| Argo CD bootstrapped, `root-app` applied | 19:46:11 |
| GPU node Ready (us-central1-a, after a scale-up failure in us-central1-c: GCE out of resources) | 19:58:12 |
| Team model (Qwen 7B, `team-demo`) Ready | 20:09:43 |

- **RTO: 46 min 11 s**, from cluster absent to model Ready. A real request
  afterwards returned HTTP 200 in 1.68 s.
- Limits: one drill, one region, one model; the time includes the wait for
  an L4 node, which depends on GCE capacity.

## Not yet

- Single region: no standby cluster, no cross-region failover.
- The state bucket is in one location; there is no copy outside it.
- No backup tool (e.g. Backup for GKE): not needed while workloads are stateless; needed the day a stateful component arrives.
