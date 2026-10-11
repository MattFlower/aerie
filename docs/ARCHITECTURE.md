# Architecture

`AerieCore` owns platform-neutral settings, counter-rate rules, fixed-capacity history, notifications' threshold state, weather data/decoding, formatting, and approximate lunar calculations. Its tests use synthetic input.

`AerieNative` is a small C boundary for Mach CPU/VM counters, 64-bit route-interface counters, libproc accounting, and read-only SMC transport. It releases Mach ports, kernel arrays, registry objects, and heap buffers. CPU accounting converts Mach absolute time to nanoseconds using the host timebase.

`AerieApp` owns AppKit status items and a reused popover, manually drawn charts and statistics, preferences, IOKit collectors, calendar integration, notifications, and weather scheduling. One utility queue serializes sampling. No periodic shell process is spawned. Core data remains independent of AppKit for a later Linux collector/UI adapter; Linux support is not implemented.

Expensive process accounting is sampled only while a dashboard is visible. System sampling uses a visible 0.5/1/2/3/5-second interval, with 100 ms tolerance. Inventory and Wi-Fi details refresh every 30 seconds. The sampler pauses during system sleep and resets counter baselines on wake. Weather requests are ephemeral, cancellable, and refreshed every 15 minutes after opt-in. Raw readings are not written to a public log.

## Native presentation

The menu uses an original ridge mark and AppKit's native control behavior. Typography is the macOS system face with aligned numeric digits. The layout is a 416-point column: module control, scrollable statistics and history, then settings/history-window controls. Sections encode metric categories rather than decorating separate cards.

Charts use blue (#246DA2) for CPU/incoming traffic, teal (#159C94) for memory, rose (#C95471) for outgoing traffic, and gold (#D39D35) for power. Backgrounds, text, separators, and focus use adaptive macOS semantic colors. This keeps system integration while making the telemetry readable in light and dark modes. Motion is limited to requested chart updates and future user-started map animation.

## Platform constraints

Driver registry statistics and SMC firmware keys vary across OS/hardware releases. The app never guesses missing values or performs fan writes. Normal-user libproc accounting can exclude protected processes. Calendar/notifications/login features have explicit permission controls. Wi-Fi SSID is unavailable where Location Services blocks it. A capability report and the remaining-work table keep these boundaries visible.
