# Teams

A team is onboarded with one pull request that adds three things:

- `argocd/apps/team-<name>.yaml`: the team's Argo CD project (only VllmService and
  FleetService, only in namespace `team-<name>`, nothing cluster-wide) and two
  applications, one for the platform-owned tenant and one for the team's services.
- `tenants/<name>/`: the namespace and the quota, owned by the platform. Today the
  quota caps GPUs, pods and VllmServices.
- `teams/<name>/`: the team's own manifests.

`ci/check-tenancy.py` fails the build if a team project can manage anything outside its
namespace, if a manifest targets another namespace, or if a tenant has no GPU quota.

Not yet: CPU and memory quotas with LimitRange defaults, enforced Pod Security, and
per-client identity and rate limits at the edge.
