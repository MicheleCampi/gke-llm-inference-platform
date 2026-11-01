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

## Not yet

- No measured RTO: the rebuild runs regularly but its duration is not recorded.
- Single region: no standby cluster, no cross-region failover.
- The state bucket is in one location; there is no copy outside it.
- No backup tool (e.g. Backup for GKE): not needed while workloads are stateless; needed the day a stateful component arrives.
