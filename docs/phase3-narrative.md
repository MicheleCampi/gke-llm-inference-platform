# Phase 3 — IaC→GitOps→inference end-to-end on a real GPU (GKE L4)

Date: 2026-06-14. Cluster `capstone-inference` (europe-west4), single L4
(`g2-standard-4`) gpu-pool, scale-to-zero. Goal: drive a real vLLM workload
(Qwen2.5-7B-Instruct) through the operator on managed GPUs, capture the
Pending→Warming→Ready signal, then `terraform destroy`. This is the only
GPU-cost phase of the capstone.

## Starting point

The `vllm-coldstart-operator` was tag v0.1.0: validated only against the CI
placeholder (gpu=0, `registry.k8s.io/pause`) on kind/K3s. It had never driven a
real vLLM pod on GPU. Phase 3 turned out to be less "apply the override" and
more "find and fix every K3s/CI assumption baked into the controller". Three
distinct bugs surfaced, each only visible at the next layer down.

## Bug 1 — RuntimeClass assumption (admission rejection)

v0.1.0 hardcoded `runtimeClassName: nvidia` whenever gpu>0. The code comment
even said "On K3s the default runtime is runc". On GKE there is no such
RuntimeClass (the cluster ships only `gvisor` and
`confidential-linked-runner`), so the API server rejected the pod outright:
`RuntimeClass "nvidia" not found`.

Root cause: GKE exposes GPUs through the device plugin with the default
container runtime; it does not use a RuntimeClass. The K3s pattern is simply
wrong on managed clusters.

Fix (v0.2.0): made `runtimeClassName` an optional spec field (`Option<String>`,
default None). GKE works out-of-box (unset); K3s users set it to "nvidia". The
operator became cluster-agnostic instead of K3s-specific.

Worth noting what did NOT need fixing: GPU scheduling. GKE runs the
ExtendedResourceToleration admission controller, which auto-injects the
`nvidia.com/gpu` toleration on any pod requesting that resource. The operator
already emitted `limits: nvidia.com/gpu: 1`, so the toleration and the
autoscaler scale-up trigger came for free — no explicit toleration or
nodeSelector required.

## Bug 2 — model passed via an env var vLLM never reads

v0.1.0 set `VLLM_MODEL` and `VLLM_ENFORCE_EAGER` as env vars. The
`vllm/vllm-openai` image does not read either: the model is a positional
argument to `vllm serve <model>`, and eager mode is the `--enforce-eager` flag.
With the placeholder pause image this never mattered (pause ignores everything);
with a real image the container would serve the wrong thing or not start.

Fix (v0.2.0): the controller now emits an explicit invocation —
`command: ["vllm", "serve"]`, then args `[model, --host 0.0.0.0, --port 8000]`,
plus `--enforce-eager` when warmupStrategy=Eager, plus a new `extraArgs` spec
field for per-deployment engine tuning. Explicit command+args so the operator
does not depend on the image entrypoint staying stable across tags. Also added a
memory-medium `/dev/shm` emptyDir (vLLM needs it) on serving pods only.

`extraArgs` carried the L4 tuning: `--max-model-len 8192`
(Qwen2.5-7B's native 32k context would over-allocate KV cache on a 24 GB L4) and
`--gpu-memory-utilization 0.90`. Kept in the resource spec, not the binary.

A GitOps gotcha here: passing extraArgs via Helm `--set` coerces `8192`/`0.90`
to numbers, but the CRD types extraArgs as array<string>; the API server would
reject the CR. Solved by writing the override as inline YAML in the ArgoCD
Application `helm.values` with the numbers quoted.

## Bug 3 — libcuda.so.1 not found (the subtle one)

With v0.2.0 deployed, the pod scheduled on the L4 (RuntimeClass gone, toleration
auto-injected) but vLLM crash-looped:

    No platform detected, vLLM is running on UnspecifiedPlatform
    Failed to import from vllm._C with ImportError('libcuda.so.1: cannot open shared object file')
    RuntimeError: Failed to infer device type

Misleading first hypotheses, both ruled out by inspection: (a) device-plugin
race at node boot — disproved, a freshly recreated pod crashed identically; (b)
driver not installed — disproved, the installer logs showed
DRIVER_VERSION=580.126.20 and "Finished installing the drivers", and the node
reported `allocatable: nvidia.com/gpu: 1`.

Root cause (confirmed via llm-d's GKE docs): vLLM's CUDA 12.8+ base image moved
the driver search path from /usr/local/nvidia to /usr/local/cuda and changed
LD_LIBRARY_PATH. But GKE mounts the NVIDIA driver at /usr/local/nvidia/lib64.
So the driver WAS mounted in the container — vLLM just wasn't looking there.

Fix (v0.2.1): inject `LD_LIBRARY_PATH=/usr/local/nvidia/lib64` on serving
(gpu>0) pods. Hardcoded (not a spec field): it's a fact of the managed-cluster
environment, not per-deployment tuning.

## The rollout deadlock

After bumping to v0.2.1, the new pod stayed Pending: the Deployment rolling
update waited for the new pod to be Ready before removing the old one, but the
new pod couldn't schedule because the single L4 (max=1) was still held by the
old crash-looping pod. Single-GPU + default rolling-update strategy = deadlock.
Resolved by deleting the old pod to free the GPU.

## Success — the numbers

Once v0.2.1's pod got the GPU:

    Automatically detected platform cuda.
    non-default args: model_tag=Qwen/Qwen2.5-7B-Instruct, max_model_len=8192, enforce_eager=True
    Time spent downloading weights: 172.0 seconds
    init engine (profile, create kv cache, warmup model) took 2.47 seconds
    Starting vLLM API server on http://0.0.0.0:8000
    Application startup complete.

VllmService status: phase=Ready, "1/1 replicas ready and warm". Pod 0 restarts.

Real completion served (OpenAI-compatible API, via port-forward):
prompt "In one sentence, what is a Kubernetes operator?" →
"A Kubernetes operator is a custom controller written in Kubernetes-native
languages like Go, which manages the lifecycle of complex applications by
defining and enforcing desired states for their components."
(usage: 39 prompt + 33 completion = 72 tokens)

End-to-end chain validated: terraform apply → GKE + GPU pool → ArgoCD
app-of-apps → operator reconciles the VllmService CR → vLLM pod on the L4 with
the driver on the loader path → weights loaded → Pending→Warming→Ready, the
signature phase-timeline metric (`vcso_vllmservice_phase`) flowing to Grafana
Cloud via Alloy. Then `terraform destroy`: 6 resources destroyed, state clean.

## Operator releases from this phase

- v0.2.0: real vLLM serving on managed GPU clusters (command/args, runtimeClassName
  from spec, extraArgs, /dev/shm).
- v0.2.1: LD_LIBRARY_PATH for managed-cluster GPU pods.

## Article angle

The honest debugging arc is the value: an operator that passed CI and kind is
not the same as an operator that runs on real managed GPUs. Three layers of
environment assumptions (admission, invocation, dynamic linker) each hid the
next. This is platform-engineering reality, not a happy-path demo.

## Open / to verify next deploy

- monitoring ignoreDifferences fix (commit e9fd20e) applied cold, not yet
  validated on a live cluster. Confirm with `argocd app diff monitoring` on next
  apply; refine the jsonPointer if a different field still drifts.
