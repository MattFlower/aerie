# Reproducible performance protocol

## Measurement

Use a release build with matching visible features, process counts, refresh intervals, and history configuration. Record UTC timestamps, OS/toolchain, hardware privately, power/thermal state, settings, process inventory, and scenario boundaries. Include every related process and helper; do not count only resident memory or omit a daemon.

`AerieMeasure` emits JSON Lines using libproc `ri_phys_footprint`, resident bytes as a separate field, CPU percentage (one logical core = 100%), and interrupt wakeups per second. It includes descendants of the selected PIDs. Related helpers launched independently must be listed explicitly. A denied/exited process marks a sample incomplete rather than silently lowering the total. The first sample has no CPU/wakeup rate baseline.

```sh
swift build --build-system native -c release --product AerieMeasure
.build/release/AerieMeasure --pids 123,456 --scenario idle --duration 60 --interval 2 > /tmp/idle.private.json
footprint -p 123 -p 456 --noCategories
top -l 31 -s 2 -pid 123 -pid 456 -stats pid,command,cpu,mem,threads,idlew,power
```

Raw output contains process names and should stay outside the repository. `footprint` may deny protected daemons; `top` can provide supplemental physical-memory evidence. Report that limitation and retain the daemon's accessible footprint/CPU evidence. `top`'s IDLEW is a different statistic from libproc interrupt wakeups; do not compare them as equivalent.

## Scenarios

1. Idle: all enabled collectors, normal menu-bar display, menus/settings closed; settle, then sample at least 60 seconds.
2. Active menu: CPU/process/history panel open, same process count and CPU display format; settle, then sample 60 seconds. Repeat for sensor-heavy and memory panels.
3. Sustained: ordinary shared-machine workload, at least 10 minutes; inspect bounded history and footprint trend without inducing CPU/GPU/storage load.
4. Settings: settings window open; measure separately from ordinary idle.
5. Maps: each implemented map layer, animation, and layer switching; include helper processes and verify release after close.

Report median, 95th percentile, and peak physical footprint, CPU, and wakeup rate. Match scenario conditions across runs. Background workload and system compression can affect measurements. A favorable early sample does not satisfy feature-complete acceptance.

## CI cost boundary

As verified on 2026-10-11, [GitHub documentation](https://docs.github.com/en/billing/concepts/product-billing/github-actions) makes standard GitHub-hosted runners free for public repositories. Larger runners are billed. CI uses `macos-15`, read-only repository permissions, no Actions artifact/cache uploads, a timeout, and concurrency cancellation. It skips when the repository is private. Account billing APIs may require an additional scope; no credentials or budgets are changed to obtain it.
