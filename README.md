# Aerie

Aerie is an original native macOS menu-bar system monitor built with Swift, AppKit, Mach, libproc, and IOKit. It runs in one process, samples through a shared scheduler, and retains bounded history.

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
- Local/removable/network volume capacity, physical disk activity, and process disk I/O.
- Interface throughput, cumulative totals, local addresses, errors, passive connectivity, and available Wi-Fi details.
- Read-only firmware temperature, fan, power, voltage, and current sensors where exposed by the hardware.
- Battery charge, time, health, cycles, electrical details, and supported peripheral batteries.
- Local/world clocks, monthly calendar, optional local calendar events, and approximate lunar phase.
- Configurable sustained threshold notifications with cooldowns and missing-data/sleep handling.
- Ten-minute detailed history, one day of minute averages, and one week of hourly averages.
- Opt-in Open-Meteo current/hourly/daily model forecasts, with attribution and explicit provider/location consent.

Some statistics require hardware or permissions that are unavailable to a normal user process. Aerie shows unavailable states and does not install an elevated helper. Detailed weather maps, official alerts, and other open requirements are tracked in the capability checklist.

## Privacy and weather

System readings stay local. Weather is off by default; Aerie does not use device location, IP geolocation, or automatic city search. Enabling weather sends your chosen coordinates (rounded to two decimal places) and network IP to Open-Meteo. Read [weather sources and terms](docs/WEATHER.md) before opting in. The free hosted API is for personal/noncommercial use; an open-source application license does not remove that restriction.

Notifications, calendar events, and launch-at-login are requested only through explicit Settings actions. Exported settings remove weather location. Public tests contain synthetic fixtures and do not make weather requests.

## Development and performance

[Architecture](docs/ARCHITECTURE.md) describes the collectors and planned Linux boundary. [Performance protocol](docs/PERFORMANCE.md) explains physical-footprint, CPU, and wakeup measurements. Raw machine measurements and screenshots should remain private.

GitHub Actions builds, tests, and lints on a standard public macOS runner. It does not upload artifacts or use Actions caches. The workflow skips private repositories so a later visibility change cannot silently consume a private-runner allowance. No paid runners or spending changes are configured.
