# PD benchmark: latency + throughput

Two scenarios for comparing PD-disaggregated and aggregated serving on the Mooncake
conversation trace (Qwen3-32B, [PDGBench](https://git.vngcloud.tech/ai-system/pdgbench)).
Each run is one aiperf call against one fresh server.

| scenario | load | read | report section |
|---|---|---|---|
| `latency.yaml` | trace on its own timestamps (3.4 req/s, 12,031 req, ~59 min) | TTFT / ITL / E2E p90, SLO met % | Latency |
| `throughput.yaml` | closed loop: CCU requests always in flight, trace gaps ignored, `ignore_eos` | input / output tok/s per CCU | Max throughput |

SLO: TTFT <= 2 s and ITL <= 30 ms (NVIDIA's goodput definition for this recipe).
Throughput: one CCU level per job (fresh server, empty KV cache); PDGBench ran
32 / 64 / 96 / 256 with 2,400 requests and 384 with 6,000.

## Run

On Slurm through srtctl, `benchmark.type: custom` (PDGBench `benchmark/recipes/`):

```sh
bash slurm/pd-bench.sh latency
bash slurm/pd-bench.sh throughput 64            # 2,400 requests
bash slurm/pd-bench.sh throughput 384 6000
```

The script makes its own venv with aiperf (vngcloud/aiperf-semi pinned commit, 0.13.0),
targets `localhost:$SRT_FRONTEND_PORT` and writes to `$ARTIFACT_DIR` (default
`/logs/artifacts`, the srtctl job log dir). Anywhere else, set `BENCH_URL`, `BENCH_TRACE`
and `ARTIFACT_DIR`, or run aiperf directly:

```sh
BENCH_URL=http://host:8000 BENCH_TRACE=data/conversation_trace.jsonl BENCH_CCU=64 \
  aiperf profile --config scenarios/pd/throughput.yaml
```

Trace: `conversation_trace.jsonl` from
[Mooncake FAST25-release](https://github.com/kvcache-ai/Mooncake/tree/main/FAST25-release/traces).

## Why aiperf-semi 0.13 and these settings

- Phase type `concurrency` (CLI `--no-fixed-schedule`): a trace with `timestamp` otherwise
  makes aiperf 0.12 replay it on its own schedule, and the concurrency is only a cap
  (PDGBench jobs 2556-2573 replayed x1 at every level).
- `ignore_trace_delays`: a finished request's slot is refilled at once.
- 0.13 honours `requests` in concurrency mode and has a warm-up phase, so no separate
  warm-up call.
