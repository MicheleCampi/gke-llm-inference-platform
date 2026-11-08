# Bootstrap (one-time, out of band)

These resources are created with `gcloud`, outside Terraform, and survive
`terraform destroy`; the CI identity, last below, is the exception: a Terraform
root of its own, applied once. `PROJECT_ID` is your project; this repository's own value
appears in `terraform/terraform.tfvars`, in the bucket name of
`terraform/versions.tf`, twice in `monitoring/grafana-secret.yaml`, in
`bootstrap/ci-identity/terraform.tfvars` and `versions.tf`, and in the service
account of `.github/workflows/plan.yml`.

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

    # The GCP service account external-secrets runs as, its access to this secret
    # and its Workload Identity binding: terraform/eso-identity.tf (terraform apply)

    # CI identity for the plan workflow (set the IDs in its terraform.tfvars)
    cd bootstrap/ci-identity && terraform init && terraform apply && cd ../..
    # The environment the plan job runs in, with you as required reviewer
    printf '%s' '{"wait_timer":0,"prevent_self_review":false,"reviewers":[{"type":"User","id":YOUR_GITHUB_USER_ID}],"deployment_branch_policy":null}' | \
      gh api -X PUT repos/OWNER/REPO/environments/terraform-plan --input -
