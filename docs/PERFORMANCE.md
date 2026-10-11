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

History export is an explicit local save-panel action and contains only the selected retained range. Minute/hour summaries retain per-metric observation counts; missing readings are not counted. Averages are sample means, not time-weighted means. Chart coordinates use elapsed time, and breaks occur after missing readings or gaps longer than three expected intervals. Backward/duplicate wall-clock readings reset retained history and aggregation baselines. No disk archive is written in the background.

Process network summaries own one built-in OS logger and temporary terminal only while the Network panel is visible. Closing/changing the panel, pausing or sleeping terminates it and clears the source/rate state; interval changes restart it. All logger descendants belong in Aerie active-view and post-close cohorts. The OS logger uses integer-second intervals: `ceil(max(1, systemInterval))`, disclosed in the panel; a 0.5-second system setting therefore reads process traffic at one second. TCP/UDP process totals include loopback and all OS-reported interfaces independently of aggregate interface selection. Protected identities are counted as unavailable, first/reset/sleep/PID-reuse rates are blank, and stale streams do not retain live rates. A fresh native kernel adapter remains a potential future replacement for the OS logger. This implementation needs real panel/active helper peak and repeated reclamation checks.

`--background --process-network-self-check` exercises twelve source ticks of logical network demand, clears demand, waits three seconds for helper release, prints only coverage/status and exits. `--background --network-demand-cycles` starts demand at 3, 68 and 133 seconds for 45 seconds each, then clears it. These explicit developer commands do not open a real menu, render its rows, change saved settings or substitute for UI acceptance; they permit repeatable source/helper lifecycle telemetry on a locked development host.

Measurement retains exited helper identities in every later record. Only a verified kernel `ESRCH` or a different known process-start identity confirms exit. A confirmed exited process has zero current footprint; CPU/wakeup rates for the transition interval remain unavailable, followed by zero for wholly post-exit intervals. Missing/protected/unidentified processes remain incomplete. Output flushes each JSON record so lifecycle transitions can be observed contemporaneously.

Storage I/O sources remain sampled at the system interval. Registry whole-media association refreshes with the existing 30-second inventory. Disk Arbitration supplies mounted volume BSD names; APFS multi-store/snapshot relationships and reported SMART status use documented read-only `diskutil list/info/apfs list -plist` queries at most once per 60 seconds while the Storage panel is visible. Commands run sequentially, have 2 MB output and 5/6-second termination/kill bounds, inherit a minimal environment and are cancelled/released on hiding, pause or sleep. Include every transient command process in active-view measurements. No diagnostic scan, repair, device write, elevated installation or new persistent permission is used. Unknown/unassociated/unsupported/failing statuses stay distinct; SMART Verified is a threshold report and does not establish remaining lifetime or a complete diagnostic pass. Drive temperature/endurance are not inferred.

`--background --storage-self-check` exercises logical read-only Storage demand, prints only coverage/status counts, clears demand and waits 7 seconds for bounded query cleanup. It does not render a real panel or substitute for active-view measurement.

Calendar controls use the configured local calendar, first weekday and week-number setting. Adjacent-month dates are selectable, month navigation clamps short/leap-month days, and selected event ranges follow calendar day boundaries through DST. Events are read only after existing full calendar access, only for the Time panel, with at most 20 displayed records per selected-day or upcoming-seven-day range. Event details stay in memory, are bounded, and clear with the native controls and EventKit store on closing/changing the panel. No event contents enter exported history or diagnostics. Ordinary open-panel refresh is once per minute, with local calendar-change invalidation; this does not alter system collector cadence. Synthetic tests cover controls, reclamation, complete grids and 23/25-hour day boundaries. Real rendering, keyboard/screen-reader interaction and an explicitly approved permission path remain pending.

Only implemented forecast providers are accepted in settings and request builders. An unsupported provider selection fails validation instead of sending its coordinates to a different service. Additional forecast providers remain an explicit capability item.

Process completeness flags cover selected and observed identities. Periodic descendant discovery can miss a command whose entire lifetime falls between external samples. Active Storage peak validation therefore also needs explicit spawn/exit registration or lifecycle tracing with timely resource samples; a closed-panel run or a poll that sees no child cannot prove its active helper budget. Keep that limitation explicit until the finite-command lifecycle measurement exists.
