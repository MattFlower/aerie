# Native detail presentation

Aerie's dashboards and drill-downs use native AppKit views with system appearance, readable value contrast and keyboard/accessibility actions. All existing collection intervals, menu composition, compact widths, upright labels, network geometry, source choices and saved settings are retained.

## Surface inventory

| Surface | Presentation |
| --- | --- |
| Overview, CPU, GPU, Memory, Storage, Network, Power | Existing compact charts/gauges and grouped facts; lighter labels and stronger readings. Long accounting explanations open through an explicit About these readings control. Missing and paused states remain visible. |
| Sensors | An exact menu-source summary, a separately identified highest live temperature, family groups and a highlighted native button for the menu reading. Every sensor remains explorable. |
| Current weather | A prominent temperature, feels-like/humidity summaries, wind/air facts, observation/forecast context and provider attribution. |
| Hourly forecast | Whole-degree temperature, grouped atmospheric facts, a cached temperature plot with actual forecast timestamps and preserved gaps, and explicit precipitation/gust windows. |
| Daily/issued-period outlook | High/Low summaries with the provider's forecast-day or daytime/following-night scope; missing extrema stay unavailable. Original issued windows and narratives remain readable. |
| Official point alert | Severity/urgency, prominent instructions, full official description, area/authority and distinct sent/effective/onset/expiry/end times. |
| Map-center alerts | Structured current point messages, prominent scope/coverage limits and full messages. Requests keep their existing consent and visibility rules. |
| CPU/GPU clock-state drill-down | Active-labelled residency and interval frequency summaries with separate state-distribution bars. This is hardware residency, separate from scheduler load. |
| Calendar event | Grouped time/location/calendar facts and a separate notes section. Closing or invalidating calendar access releases the details. |
| Reading explanations | A secondary, readable explanation view. The original text remains available. |
| Source & diagnostics | Explicit secondary control for exact timestamps, firmware identities, full provider qualifiers and source precision. Copy details includes the complete presentation. |
| Settings, map controls, history tools, permission/error dialogs | Existing native editing/navigation controls and guardrails remain available. These require live review alongside the redesigned reading surfaces. |

## Temperature conventions

Weather temperatures, apparent temperature, dew point, hourly/daily/issued-period temperatures and menu readings use whole degrees in Fahrenheit and Celsius. Data stays in its original precision; rounding happens only at presentation. Exact source values remain available in secondary diagnostics where provided. Negative zero is displayed as zero; nonfinite/missing temperatures remain unavailable.

Hardware temperatures retain one decimal in the chosen unit. Firmware values and native units remain available in individual sensor diagnostics; voltage/current/power precision is unchanged.

## Menu temperature identity

The existing menu value is the first finite live temperature in the current inventory order. The detail panel now uses the same selection. Its label is TMP when the role is unknown; CPU or GPU appears only for an explicit mapped source label. A local alias does not infer a hardware role from an unknown firmware key. The tooltip and accessibility description name the exact selected source. The sensor inventory highlights that source and every reading opens its own facts and raw identity. Highest-temperature history/rules remain separate aggregates; graph tooltips disclose that scope.

## Validation and remaining work

Synthetic light/dark content renders cover every dashboard and representative drill-downs. They contain generated data and exclude native window chrome; they are layout evidence, not screenshots of a live user's device. Public CI checks minimum-OS and Intel builds, accessibility actions, source selection, weather precision, missing states, timing and content release. A rollout and real native window/keyboard/VoiceOver review remain necessary. Current-condition dew point, UV and visibility are not yet in the current report model; hourly forecasts expose these fields when provided. This is an implementation coverage gap and does not establish that a provider lacks the observations. The detail-window change has no new timer, provider, helper, location or privacy grant. Physical footprint, CPU and wakeups still require the separate release acceptance protocol; synthetic UI tests do not establish the memory target.
