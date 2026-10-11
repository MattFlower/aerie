# Reproducible performance protocol

## Measurement

Use a release build with matching visible features, process counts, refresh intervals, and history configuration. Record UTC timestamps, OS/toolchain, hardware privately, power/thermal state, settings, process inventory, and scenario boundaries. Include every related process and helper; do not count only resident memory or omit a daemon.

`AerieMeasure` emits JSON Lines using libproc `ri_phys_footprint`, resident bytes as a separate field, CPU percentage (one logical core = 100%), and interrupt wakeups per second. It retains every observed PID plus process-start identity, including exited or reparented descendants. PID reuse cannot inherit a previous identity or rate baseline. Related helpers launched independently must be listed explicitly. A denied/exited identity marks affected metrics incomplete rather than silently lowering totals. Physical footprint, CPU and wakeups each have a completeness flag; incomplete totals are JSON null. The first sample and newly observed helpers have no CPU/wakeup baseline and are incomplete for those metrics. Record helpers present before launch as explicit selected PIDs. Historical measurements made before these completeness fields existed must retain their caveats; do not rewrite raw evidence.

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

## Network scope and counter continuity

Native interface collection remains complete at the chosen system interval. Network Settings can select which active interfaces feed aggregate bandwidth, history and download/upload rules; unselected interfaces are still sampled and displayed. The default sums all active interfaces, which can duplicate traffic through virtual tunnels. Choosing one side avoids that aggregation duplication without reducing collection. Changing scope clears only download/upload history and their pending aggregates, preserving CPU, temperature and other series.

Observed session totals begin at zero at each interface's first reading; prelaunch cumulative traffic is not credited. Counter rollback/wrap or a 32/64-bit source change rebases that interface at zero and shows a new baseline time. Disappearance or a failed complete interface read clears its observation session. These are per-interface observed sessions, not a permanent whole-machine usage ledger. Source failures stay unavailable. Synthetic tests cover large 64-bit cumulative values, source continuity, missing interfaces, scope changes and isolated history clearing. Full-interface native regressions remain mandatory for every build.

## Sensor sampling configuration

Full hardware-sensor sampling remains the default for new and legacy settings. Every supported source is read at the chosen system interval; failed readings stay in the inventory with unavailable values. An explicit General Settings option can defer fans, power, voltage and current until the Sensors panel needs them. It always samples every temperature at the original interval because maximum-temperature history and threshold rules require them. Opening Sensors restores all families at that same cadence; closing it removes deferred live values instead of reusing stale values or treating them as zero. There is no automatic battery/low-power sampling reduction.

Disclose this option in every measurement. A run using on-demand sensor families is a different configuration from full sampling and cannot prove full-sampling feature/performance acceptance. The development-only `--sensor-sampling-demand` launch argument applies the option for that process without saving it; `--background --self-check` reports inventory, live/deferred source counts, temperature coverage, network counter width and interval. It does not exercise a real open panel. Synthetic regressions verify identical temperature history/rule inputs, full inventory retention, visible-panel restoration and missing-value semantics. Real panel transitions still need UI validation.

## CI cost boundary

As verified on 2026-10-11, [GitHub documentation](https://docs.github.com/en/billing/concepts/product-billing/github-actions) makes standard GitHub-hosted runners free for public repositories. Larger runners are billed. CI uses `macos-15`, read-only repository permissions, no Actions artifact/cache uploads, a timeout, and concurrency cancellation. It skips when the repository is private. Account billing APIs may require an additional scope; no credentials or budgets are changed to obtain it.

Map HTTP transfers enforce their response byte budget while receiving chunks, including unknown-length responses. A rejected body does not enter the raster cache; suspension cancels in-flight and paced work. Synthetic tests cover exact-limit responses, oversize headers, chunk overflow, cancellation and subsequent recovery. Real active/post-close peaks remain pending.
