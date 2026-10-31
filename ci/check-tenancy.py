"""Each team is confined to its namespace and has a GPU quota owned by the platform."""
import glob, os, sys
import yaml

root = sys.argv[1] if len(sys.argv) > 1 else "."
REPO = "git@github.com:MicheleCampi/gke-llm-inference-platform.git"
GROUP = "inference.michelecampi.dev"
errs = []


def docs(path):
    with open(path) as f:
        return [d for d in yaml.safe_load_all(f) if d]


files = sorted(glob.glob(os.path.join(root, "argocd/apps/team-*.yaml")))
if not files:
    errs.append("no team found in argocd/apps/team-*.yaml")
for f in files:
    t = os.path.basename(f)[len("team-"):-len(".yaml")]
    ns = "team-" + t
    ds = {(d["kind"], d["metadata"]["name"]): d for d in docs(f)}
    p = ds.get(("AppProject", ns))
    if not p:
        errs.append(f"{t}: no AppProject {ns}")
        continue
    s = p["spec"]
    if s.get("clusterResourceWhitelist"):
        errs.append(f"{t}: team project may manage cluster-scoped resources")
    for k in s.get("namespaceResourceWhitelist") or []:
        if k.get("group") != GROUP:
            errs.append(f"{t}: team project may manage {k.get('kind')}")
    if [d.get("namespace") for d in s.get("destinations") or []] != [ns]:
        errs.append(f"{t}: team project destinations are not exactly {ns}")
    if s.get("sourceRepos") != [REPO]:
        errs.append(f"{t}: team project sourceRepos are not exactly this repository")
    for app, proj, path in (("tenant-" + t, "tenancy", "tenants/" + t), (ns, ns, "teams/" + t)):
        a = ds.get(("Application", app))
        if not a:
            errs.append(f"{t}: no Application {app}")
            continue
        sp = a["spec"]
        if sp.get("project") != proj or sp["source"].get("path") != path or sp["destination"].get("namespace") != ns:
            errs.append(f"{t}: Application {app} must use project {proj}, path {path}, namespace {ns}")
    ten = [d for g in sorted(glob.glob(os.path.join(root, "tenants", t, "*.yaml"))) for d in docs(g)]
    if not any(d["kind"] == "Namespace" and d["metadata"]["name"] == ns for d in ten):
        errs.append(f"{t}: tenants/{t} has no Namespace {ns}")
    if not any(d["kind"] == "ResourceQuota" and d["metadata"].get("namespace") == ns
               and "requests.nvidia.com/gpu" in d["spec"].get("hard", {}) for d in ten):
        errs.append(f"{t}: tenants/{t} has no GPU quota")
    # The operator sets only the GPU limit, so CPU/memory are capped by quota and
    # filled in by LimitRange defaults; without the defaults every pod is rejected.
    if not any(d["kind"] == "ResourceQuota" and d["metadata"].get("namespace") == ns
               and {"requests.cpu", "requests.memory"} <= set(d["spec"].get("hard", {})) for d in ten):
        errs.append(f"{t}: tenants/{t} quota does not cap CPU and memory")
    if not any(d["kind"] == "LimitRange" and d["metadata"].get("namespace") == ns
               and any({"cpu", "memory"} <= set(l.get("defaultRequest", {}))
                       and {"cpu", "memory"} <= set(l.get("default", {}))
                       for l in d["spec"].get("limits", []) if l.get("type") == "Container")
               for d in ten):
        errs.append(f"{t}: tenants/{t} has no LimitRange with CPU/memory defaults for containers")
    for g in sorted(glob.glob(os.path.join(root, "teams", t, "*.yaml"))):
        for d in docs(g):
            if d["metadata"].get("namespace", ns) != ns:
                errs.append(f"{t}: {os.path.relpath(g, root)} targets namespace {d['metadata']['namespace']}")
for e in errs:
    print("FAIL:", e)
if errs:
    sys.exit(1)
print(f"tenancy OK: {len(files)} team(s)")
