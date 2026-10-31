"""Onboard a team: python3 ci/new-team.py <name> [--gpu N]

Writes tenants/<name>, argocd/apps/team-<name>.yaml and teams/<name>/ from the
demo team, the reference tenant. ci/check-tenancy.py then verifies the result.
"""
import argparse, glob, os, re, sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ap = argparse.ArgumentParser()
ap.add_argument("name")
ap.add_argument("--gpu", type=int, default=1)
a = ap.parse_args()
t = a.name
if not re.fullmatch(r"[a-z][a-z0-9-]{0,19}", t) or t == "demo":
    sys.exit(f"invalid team name: {t!r} (lowercase, digits, dashes, max 20)")
if not 0 <= a.gpu <= 8:
    sys.exit("--gpu must be between 0 and 8")
out = {
    os.path.join("argocd/apps", f"team-{t}.yaml"): os.path.join("argocd/apps", "team-demo.yaml"),
}
for f in sorted(glob.glob(os.path.join(root, "tenants/demo/*.yaml"))):
    out[os.path.join("tenants", t, os.path.basename(f))] = os.path.relpath(f, root)
if os.path.exists(os.path.join(root, "tenants", t)) or os.path.exists(os.path.join(root, "teams", t)) \
        or os.path.exists(os.path.join(root, "argocd/apps", f"team-{t}.yaml")):
    sys.exit(f"team {t} already exists")

subs = [("tenants/demo", f"tenants/{t}"), ("teams/demo", f"teams/{t}"),
        ("tenant-demo", f"tenant-{t}"), ("team-demo", f"team-{t}"),
        ("team: demo", f"team: {t}"), ("Team demo", f"Team {t}")]
written = {}
for dst, src in out.items():
    s = open(os.path.join(root, src)).read()
    for x, y in subs:
        s = s.replace(x, y)
    if dst.endswith("quota.yaml"):
        s, n = re.subn(r"(requests\.nvidia\.com/gpu: )'\d+'", rf"\g<1>'{a.gpu}'", s)
        if n != 1:
            sys.exit("quota template: GPU line not found")
    if re.search(r"\bdemo\b", s):
        sys.exit(f"{dst}: a reference to the demo team survived the template")
    written[dst] = s
for dst, s in written.items():
    os.makedirs(os.path.dirname(os.path.join(root, dst)), exist_ok=True)
    open(os.path.join(root, dst), "w").write(s)
os.makedirs(os.path.join(root, "teams", t), exist_ok=True)
open(os.path.join(root, "teams", t, ".gitkeep"), "w").close()
print(f"team {t}: {len(written)} files + teams/{t}/; next: python3 ci/check-tenancy.py, then a PR")
