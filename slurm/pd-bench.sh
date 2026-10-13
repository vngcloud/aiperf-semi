#!/bin/bash
# Run a PD benchmark scenario (scenarios/pd/) inside a srtctl job.
#
#   pd-bench.sh latency                      # trace on its own timestamps
#   pd-bench.sh throughput CCU [REQUESTS]    # closed loop, CCU in flight (default 2400 requests)
#
# srtctl recipe (benchmark.type: custom), see PDGBench benchmark/recipes/:
#   command: bash /mnt/pdgbench/aiperf-service/slurm/pd-bench.sh throughput {ccu}
#
# Env (all optional):
#   BENCH_URL, BENCH_MODEL, BENCH_TOKENIZER, BENCH_TRACE      scenario inputs (see the yaml)
#   BENCH_SLO_TTFT_MS, BENCH_SLO_ITL_MS                        default 2000 / 30
#   AIPERF_SPEC      pip spec for aiperf (wheel path or git URL), default the pinned commit below
#   ARTIFACT_DIR     parent of the run dir, default /logs/artifacts (srtctl job logs)
#   SRT_FRONTEND_PORT, AIPERF_SERVER_METRICS_URLS              set by srtctl
set -euo pipefail
export PYTHONUNBUFFERED=1

HERE="$(cd "$(dirname "$0")/.." && pwd)"
MODE=${1:?usage: pd-bench.sh latency | throughput CCU [REQUESTS]}
case "$MODE" in
  latency) ;;
  throughput)
    export BENCH_CCU=${2:?throughput needs CCU}
    export BENCH_REQUESTS=${3:-2400} ;;
  *) echo "unknown mode: $MODE" >&2; exit 2 ;;
esac

# vngcloud/aiperf-semi main as of 2026-10-11 (aiperf 0.13.0): the commit the PDGBench report ran on.
AIPERF_SPEC=${AIPERF_SPEC:-git+https://github.com/vngcloud/aiperf-semi@de6ca1d6aa109e95ff4c310ce52b2a1ccfa13fca}
export BENCH_URL=${BENCH_URL:-http://localhost:${SRT_FRONTEND_PORT:-8000}}
export BENCH_MODEL=${BENCH_MODEL:-Qwen/Qwen3-32B}
model_base=${BENCH_MODEL##*/}
run=${model_base}_${MODE}${BENCH_CCU:+_ccu${BENCH_CCU}}_$(date '+%Y%m%d_%H%M%S')
export BENCH_ARTIFACT_DIR="${ARTIFACT_DIR:-/logs/artifacts}/${run}"
mkdir -p "$BENCH_ARTIFACT_DIR"

ulimit -n 600000 2>/dev/null || ulimit -n 65536 2>/dev/null || true
export AIPERF_HTTP_SO_RCVTIMEO=120

# Own venv per job: the container rootfs is read-only and workers share $HOME.
if ! command -v uv >/dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
venv=${TMPDIR:-/tmp}/aiperf-${SLURM_JOB_ID:-$$}
uv venv -q -p 3.12 "$venv"
uv pip install -q -p "$venv" "$AIPERF_SPEC" tiktoken
export PATH="$venv/bin:$PATH"

extra=()
if [ -n "${AIPERF_SERVER_METRICS_URLS:-}" ]; then
  IFS=',' read -r -a urls <<< "$AIPERF_SERVER_METRICS_URLS"
  extra=(--server-metrics "${urls[@]}" --server-metrics-formats json jsonl)
fi

echo "pd-bench $MODE ccu=${BENCH_CCU:-} requests=${BENCH_REQUESTS:-trace} url=$BENCH_URL"
echo "aiperf $(aiperf --version) from $AIPERF_SPEC -> $BENCH_ARTIFACT_DIR"
aiperf profile --config "$HERE/scenarios/pd/$MODE.yaml" "${extra[@]}"
ls -la "$BENCH_ARTIFACT_DIR"
