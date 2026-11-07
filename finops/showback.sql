-- Showback per Kubernetes namespace from the GCP detailed billing export.
-- Run: bq query --use_legacy_sql=false --parameter=start:DATE:YYYY-MM-DD --parameter=end:DATE:YYYY-MM-DD < finops/showback.sql
-- Scope: rows labelled cost-center=inference (set by terraform/modules/gke-gpu resource_labels).
-- Rows without k8s-namespace are cluster and node costs not attributed to a pod.
SELECT
  DATE(usage_start_time) AS day,
  IFNULL((SELECT value FROM UNNEST(labels) WHERE key = 'k8s-namespace'), '(cluster/node, unattributed)') AS namespace,
  ROUND(SUM(cost), 4) AS cost,
  ROUND(SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)), 4) AS credits,
  ROUND(SUM(cost) + SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)), 4) AS net,
  ANY_VALUE(currency) AS currency
FROM `rosy-precinct-477218-u8.billing_export.gcp_billing_export_resource_v1_01C5CE_4BA196_F74811`
WHERE DATE(usage_start_time) BETWEEN @start AND @end
  AND EXISTS (SELECT 1 FROM UNNEST(labels) WHERE key = 'cost-center' AND value = 'inference')
GROUP BY day, namespace
ORDER BY day, net DESC
