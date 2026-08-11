# Profiling Baselines

Performance changes are evaluated against repeatable workloads, not one-off frame observations.

## Workloads

- `profiling_baseline`: spawns the configured twenty-raider combat scene and the full camp population, samples 180 headless frames for each, and prints `RAID_PROFILE_BASELINE` JSON.
- `command_decoder_corpus`: reports deterministic and weighted decoder latency over the complete command corpus.
- `who_resolution_corpus`: reports target-resolution accuracy and latency over the complete Who corpus.

Run them on the same machine and Godot build:

```powershell
./tools/run_regressions.ps1 -GodotPath <path-to-godot> -Filter profiling_baseline
./tools/run_regressions.ps1 -GodotPath <path-to-godot> -Filter corpus
```

Record the Godot version, build type, CPU, OS, and emitted JSON when investigating a regression. Take at least three runs and compare medians. Optimize only when the same workload regresses consistently; these profiling samples intentionally report measurements without imposing hardware-dependent CI thresholds.

## Reference Sample

Recorded 2026-08-10 with Godot 4.7.1-stable (official), Windows, headless mode, and an AMD Ryzen 7 9800X3D. These are comparison anchors, not CI limits.

| Workload | Sample | Result |
| --- | --- | --- |
| Twenty-raider combat | 180 frames | 7.810 ms average frame |
| Full camp population | 180 frames | 6.858 ms average frame |
| Command decoder corpus | 95 commands, 100% correct | 2.149 ms deterministic; 17.348 ms weighted average |
| Who resolver corpus | 32 samples, 100% correct | 1.458 ms overall; 0.607 ms weighted average |
