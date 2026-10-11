# Capability and acceptance checklist

Updated 2026-10-11. A check marks implementation, not complete hardware coverage or final acceptance.

| Area | Implemented | Remaining validation or work |
| --- | --- | --- |
| CPU | User/system, per-core, topology counts, load, uptime, process CPU; bounded CPU-complex/core clock-state distributions with per-state details | Verified dynamic frequency mapping, grouped scheduler utilization/role labels, CPU temperatures by role; multiple CPU architectures |
| GPU | Published utilization, renderer/tiler, shared memory, refreshed accelerator inventory; separate system GPU clock-state distributions | Per-process GPU, global FPS, frequencies/temperatures where not published; multi-GPU validation |
| Memory | App/wired/compressed/free/cache/purgeable, pressure state, paging, swap, process physical footprint | Validate accounting against OS tools on more hardware; pressure percentage needs an honest definition |
| Storage | Mounted volume capacity/kind, important-use space, per-source device rates, native volume BSD names, APFS backing associations, OS-reported SMART fallback, process I/O, 30-second device/mount inventory and topology rate reset | Drive temperature/endurance from supported telemetry, broader SMART/NVMe coverage, real metadata/device UI and hot-plug hardware validation |
| Network | Complete interface rates/totals/IP/errors, configurable aggregate interface selection, per-interface observed sessions, visible-panel OS TCP/UDP process summaries, passive connection state and available Wi-Fi details | Optional public IP, expanded Wi-Fi permission path; real filter/session/process UI, helper peaks/reclamation and topology validation |
| Sensors | Read-only SMC temperature/fan/power/voltage/current inventory; full default sampling, optional demand reads, local key-preserving aliases and individual native-unit thresholds | Verified hardware-role labels, missing firmware formats, frequency/light channels, more hardware; safe optional fan profiles need separate approval and implementation |
| Battery/power | Battery health/cycles/time/electrical details, Low Power Mode state, registry peripherals, process wakeups | Power-mode controls, energy impact/process attribution, multiple sources/UPS and peripheral testing |
| Time | Format, local/world clocks, native selectable month/week calendar with navigation and rollover-following Today, selected-day/upcoming local events with details and calendar filtering, offline approximate moon and separately configured solar-noon/daylight/twilight estimates | Real calendar/event/selection UI and permission validation, broader solar-reference/edge validation and accurate lunar ephemeris, clock styles/advanced calendar options |
| Weather | Opted-in Open-Meteo model current/hourly/daily/daylight or NWS station observations/hourly/named periods/current point-alert messages; location timezones, bounded receipt, exact-provider redirects, native period/alert details | Live opt-in and native detail-window validation; broader provider/coverage choices, fuller hourly details and provider-specific measurements |
| Weather maps | On-demand native radar/satellite animation, NHC tropical tracks, official alert overlay, forecast wind barbs/speed/temperature/6-hour precipitation/snow; provider legends/times/coverage, bounded current point-alert message details, 12-frame decoded-cost cache | Real UI and animation QA, active peaks and repeated post-close reclamation; convective-cell tracks, richer per-polygon alert inspection; acceptance of regional US product coverage |
| Rules | Sustained thresholds, individual edit/delete/enable controls, cooldown, missing-data/sleep reset; connectivity/power/charging/Low Power Mode/thermal/volume/DST/time-zone changes | Notification delivery permission validation; native alias/rule UI and missing-key/reconnection validation; richer rule conditions |
| Menu/configuration | Independent or ordered 1–6-module combined items; text/graph/compact/native two-line styles, per-item RGB colors, explicit layout-aware global shortcuts, ordering/visibility, theme, units, spacing, refresh, import/export | Real menu/style/color/composition/shortcut QA and accessibility, reset/migration and selection state |
| History | Fixed-capacity detailed/minute/hourly series, timestamp-based gap-aware charts, native zoom/pan, click-to-inspect, observed aggregate counts, visible-range CSV export and opt-in bounded restart checkpoints | Real persistence/export/chart/zoom UI QA; final-configuration matched sustained acceptance |
| Delivery | Local ad-hoc app packaging, public CI | Notarization is outside the current authorized scope; Intel and minimum-OS CI coverage |

## Required acceptance

- Every feature must be implemented, or have an explicit hardware/OS/permission constraint agreed for acceptance. Merely putting an unfinished feature in this table does not satisfy the requirement.
- Collector values must agree with accessible OS evidence and synthetic accounting tests. Unavailable, stale, and zero must remain distinguishable.
- Real menus/settings must be validated visually and with accessibility; imported settings must reject invalid data.
- All application and helper background/idle physical footprints must remain within the agreed background memory budget with comparable configuration and intervals. Active menus, settings, and maps may use reasonable temporary headroom, with measured peaks, prompt post-close settling, and repeated open/close checks for retained caches or leaks. Feature omissions do not establish a passing result.
- CPU, interrupt wakeups, and measurement limitations must be reported, with no disruptive load generator.
- Final commits must pass build, meaningful synthetic tests, lint, UI checks, and available performance checks. Public CI must stay within free standard-runner entitlement.
- Final acceptance is required before completion or repository privatization.
