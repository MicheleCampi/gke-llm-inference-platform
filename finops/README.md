# FinOps: showback per team

`showback.sql` reads the GCP detailed billing export and splits cost by Kubernetes namespace. Each team is a namespace (`team-<name>`), so the namespace row is the team's showback.

## Run

    bq query --project_id=rosy-precinct-477218-u8 --use_legacy_sql=false \
      --parameter=start:DATE:2026-11-05 --parameter=end:DATE:2026-11-05 < finops/showback.sql

## Reference result (B-007, 2026-11-05, read 2026-11-07)

- Sum of `net`: 0.1194 EUR, equal to Compute Engine 0.0479 + Kubernetes Engine 0.0715 for that day.
- `(cluster/node, unattributed)` 0.0815, `kube:unallocated` 0.0195, `kube-system` 0.0095, `goog-k8s-unknown` 0.0047, `kube:system-overhead` 0.0040.
- `team-demo` and `team-b`: 0.0. No serving pod ran in B-007, so team cost is not yet measured.

## Validity envelope and limits

- Scope: only rows labelled `cost-center=inference`. Networking and Logging rows of that day (0.0002 EUR) carry no such label and are excluded.
- The cluster is created with five resource labels (plan of run 42089402338, job 127463178436); only `cost-center` and `environment` reach the export. `team`, `project`, `managed-by` and node `pool` do not. Cause not known.
- Team attribution uses `k8s-namespace` from GKE cost allocation, not the cluster `team` label.
- The export lags by about a day and can still be corrected; results are provisional for recent days.
- Values are rounded to 4 decimals per row.
