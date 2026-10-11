# Aerie

Aerie is an original native macOS menu-bar system monitor built with Swift, AppKit, Mach, libproc, and IOKit. The application samples through a shared scheduler and retains bounded history. Visible Network and Storage panels can own temporary built-in OS command processes; these are included in its performance accounting.

**Development preview:** the application is runnable, but the full feature and performance acceptance checklist is still open. See [capabilities and remaining work](docs/CAPABILITIES.md).

## Build and run

Requires macOS 14 or newer and Xcode's command-line tools. There are no package dependencies, accounts, API keys, or paid signing requirements.

```sh
swift test --build-system native
bash scripts/build-app.sh
open dist/Aerie.app
```

The build is ad-hoc signed for local development. It is not notarized or submitted to the App Store. Left-click a menu item to inspect its dashboard. Right-click for settings, sampling pause, Activity Monitor, or quit. Configure independent items or one combined item, text/graph/compact styles, units, order, appearance, refresh interval, rules, and world clocks in Settings.

## Current capabilities

- CPU utilization, user/system split, logical-core bars, topology, load, uptime, and top processes.
- Driver-exposed GPU utilization, rendering/tiling activity, and shared-memory use.
- Memory categories, OS pressure state, compression, swap, paging, and top process footprints.
- Local/removable/network volume capacity, per-source disk activity, mounted-volume/APFS backing associations, read-only OS-reported SMART status, and process disk I/O.
- Complete interface throughput, cumulative and observed-session totals, aggregate interface selection, local addresses, errors, passive connectivity, and available Wi-Fi details.
- Read-only firmware temperature, fan, power, voltage, and current sensors where exposed by the hardware; full sampling by default with an explicit on-demand option for non-temperature families.
- Battery charge, time, health, cycles, electrical details, and supported peripheral batteries.
- Local/world clocks, selectable monthly calendar with navigation and week numbers, optional selected-day/upcoming local event details, and approximate lunar phase.
- Editable sustained threshold notifications and system-state change rules, with cooldowns and missing-data/sleep handling.
- Ten-minute detailed history, one day of minute averages, and one week of hourly averages.
- Opt-in Open-Meteo current/hourly/daily model forecasts or US NWS station observations, hourly/named-period forecasts and current point-alert details, with explicit provider/location consent.
- Separately opted-in native NOAA weather maps: observed radar, satellite bands, tropical tracks, official alert overlays, wind barbs/speed, temperature, precipitation and snow forecasts, plus current point-alert messages with distinct sent/effective/onset/expiry/end times.

Some statistics require hardware or permissions that are unavailable to a normal user process. Aerie shows unavailable states and does not install an elevated helper. Regional weather coverage, per-polygon alert inspection, visual validation and other open requirements are tracked in the capability checklist.

## Privacy and weather

System readings stay local. Forecasts and maps are off by default; Aerie does not use device location, IP geolocation, or automatic city search. Enabling forecasts sends your chosen coordinates (rounded to two decimal places) and network IP only to the selected provider. Map consent is separate and sends the selected map extent and IP to NOAA/NWS services while the map is visible. Opening map alert details also sends its rounded center point to NWS. Read [weather sources and terms](docs/WEATHER.md) before opting in. Open-Meteo's free hosted API is for personal/noncommercial use; an open-source application license does not remove that restriction. NWS coverage is principally US land forecasts and advertised observation stations.

Notifications, calendar events, and launch-at-login are requested only through explicit Settings actions. Exported settings remove weather location. Public tests contain synthetic fixtures and do not make weather requests.

## Development and performance

[Architecture](docs/ARCHITECTURE.md) describes the collectors and planned Linux boundary. [Performance protocol](docs/PERFORMANCE.md) explains physical-footprint, CPU, and wakeup measurements. Raw machine measurements and screenshots should remain private.

GitHub Actions builds, tests, and lints on a standard public macOS runner. It does not upload artifacts or use Actions caches. The workflow skips private repositories so a later visibility change cannot silently consume a private-runner allowance. No paid runners or spending changes are configured.

History charts use elapsed timestamps and leave missing or long sampling gaps visible. Export the retained time range as local CSV with explicit units, UTC dates, aggregate source scope and observed sample counts. Export does not transmit data or start background archiving.

Per-process TCP/UDP traffic uses one macOS-provided `nettop` process while the network panel is visible. No elevated helper is installed. Its independent summary scope includes loopback and does not follow the aggregate interface filter. Process-start identities, bounded CSV state and missing/reset baselines prevent attributing a previous process’s traffic to a reused PID.
