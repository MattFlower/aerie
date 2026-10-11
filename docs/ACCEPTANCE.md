# Release acceptance

Aerie remains a development preview. Synthetic tests establish specific software behavior; they do not establish complete hardware coverage, real-window behavior or the background memory budget. Completion and repository privatization require final acceptance.

## Open macOS capabilities

| Area | Outstanding implementation or constraint |
| --- | --- |
| CPU | Dynamic GHz needs a verified frequency table/state mapping. Topology counts and per-core load exist; grouping scheduler load and temperatures by verified hardware role remains partial. Raw clock states do not establish those roles. |
| GPU | Per-process GPU attribution is absent. Device FPS/frequency/temperature depend on published driver fields; global FPS and broader multi-GPU coverage remain unverified. |
| Memory | OS pressure categories and used-memory percentage exist. A quantitative pressure percentage needs a defined, validated source; used-memory percentage is not pressure. |
| Storage | OS-reported SMART status exists. Drive temperature/endurance and broader SMART/NVMe telemetry remain partial; hot-plug and more hardware need validation. |
| Network/processes | Interface and visible TCP/UDP process rates, optional application/executable combining, and per-panel process sorting exist. Real enabled grouping/filter/session/topology behavior, source cost and protected-process coverage need validation. |
| Sensors | Exposed temperature/fan/electrical channels exist. Frequency/light formats and verified role labels remain partial. Fan profiles are absent and need a reviewed control implementation and separate write authorization. |
| Power | Battery/UPS inventory, electrical readings and wakeup ranking exist. Energy-impact attribution and energy-mode controls are absent. UPS/multiple batteries/peripherals require hardware validation; wakeups are not energy impact. |
| Time | Month navigation, week numbers, world clocks, local events and approximate solar/lunar information exist. Accurate lunar ephemeris, more clock styles and advanced calendar options remain open. Event access needs separate consent. |
| Weather/maps | Current forecasts, period/alert details and nine map types exist. Fuller hourly details, convective-cell tracks and per-polygon alert inspection remain partial or absent. Regional coverage and enabled-source behavior require acceptance and live validation. |
| Rules/configuration/history | Threshold/change rules, styles/colors/shortcuts, import/export and bounded history exist. Richer conditions and reset/migration controls remain open. Notification delivery, native configuration actions and real export/persistence need validation. |

These are not all permission failures. Source mapping, missing product behavior and hardware coverage remain engineering work. Linux is a later platform direction and is outside this macOS release checklist.

## Inputs and optional-source consent

- An unlocked desktop is required for real UI checks.
- **NWS validation:** separately authorize `--nws-integration-fixture` at the public point **39.75, -97.09**, and temporary native forecast settings named **Public development fixture**. This sends only the fixed rounded point and network IP to **api.weather.gov**, without device location or credentials. There are at most eight sequential requests per refresh, a 2 MB response bound, no immediate retry and at most one refresh per 15 minutes. Native period/alert details make no extra forecast requests. Restore forecasts off and clear the fixture afterward.
- **NOAA map validation:** separate consent covers `--map-integration-fixture` at **west −125, south 24, east −66, north 50**, with point alerts at **40, −100**. Native map validation can use that public center with forecasts off: its initial 16-degree viewport is **west −108, south 32, east −92, north 48**. Zoom/pan changes the public viewport sent to **opengeo.ncep.noaa.gov**, **nowcoast.noaa.gov** or **mapservices.weather.noaa.gov**; alert details send the rounded public center to **api.weather.gov**. Validate only public test viewports. Requests are paced by at least 750 ms; visible refresh is 120 seconds and decoded playback retains at most 12 frames within 16 MiB. Restore maps off and clear the fixture afterward.
- Recheck the selected service/product terms and attribution in [weather sources](WEATHER.md) before those requests. Neither consent selects Open-Meteo or grants calendar, notification, Wi-Fi identity, external-address lookup, launch-at-login, device location, fan/power controls, elevated-helper installation or persistent access. Those are separate choices. Do not create credentials, subscriptions or security exceptions.

## Final checks

1. Resolve every implementation gap above, or explicitly agree a supported hardware/OS/coverage constraint. A listed gap alone is not acceptance.
2. On the final commit, validate every menu, Settings action and supported detail view visually and through accessibility. Check unavailable/stale/zero states, Power time context, full long-inventory traversal, calendar navigation, charts/zoom/pan, rules, styles/colors/order, shortcuts and settings/history import/export. Optional-source checks require their own consent.
3. Match enabled features, process counts, collector intervals and full retained history for physical-footprint measurements. Record settings and UTC scenario boundaries privately. Do not omit helpers, slow sampling silently or compare Settings-open/minimized states with closed-window idle.
4. Measure final release builds with optional diagnostics **off**: at least 60 seconds closed idle, 60 seconds in each representative active panel, and ten minutes of ordinary sustained sampling. Measure Settings and enabled maps/forecast sources separately. Repeat paired open/fully-close/settle cycles at least three times and inspect retained-footprint trends. Confirm the agreed all-process background ceiling; disclose temporary active headroom and settling behavior.
5. Include every observed/registered helper, process-start identity, confirmed exit and unreadable metric. Report median, p95 and peak footprint, CPU and interrupt wakeups. Protected roots, uncertain cadence, locked/sleeping intervals and unobserved transient peaks remain explicit limitations. Do not add nonsimultaneous lifetime peaks or substitute RSS for physical footprint.
6. Pass synthetic tests, strict lint, release packaging/signature checks and all public macOS CI jobs for the exact final commit. Public CI uses synthetic fixtures only; real machine data and screenshots stay outside the repository.

See [capabilities](CAPABILITIES.md) for the implemented inventory and [performance protocol](PERFORMANCE.md) for reproducible measurement details.
