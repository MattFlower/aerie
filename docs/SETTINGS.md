# Settings and menu appearance

Aerie's resizable Settings window has a left sidebar and scrolling native forms. Changes stay in a draft until **Apply**; **Close** discards unapplied edits. Imported profiles and Restore Defaults are reviewed before staging.

- **General:** collection interval, full or on-demand sensor sampling, process grouping/sorting, units, theme, numeric history and configuration transfer.
- **Menu Bar:** grouped modules, separate items or the existing combined dashboard; visibility/order/style/color; automatic, inline, vertical or icon labels. Inside padding and gaps between grouped modules have separate controls. Aerie controls only its own grouped gaps; macOS places separate items.
- **Network:** choose All, Selected or None from a readable interface list. Saved missing interfaces remain selectable. Every interface continues to be sampled; this choice changes aggregate bandwidth, history and speed notifications. Optional external-address lookup has its own consent.
- **Weather:** manually enter a point, explicitly find a city/ZIP through Apple geocoding, or request one Mac location through macOS. Ambiguous results require a selection. A chosen point can also fill daylight. Forecasts, maps and daylight remain under their own switches. Unconfigured weather stays hidden; a configured item remains stable when data is unavailable.
- **Date & Time:** follow Mac date/time format and zone by default, or type a custom format and see its example update. Existing custom formats are preserved. Configure world clocks, calendar/event display and offline daylight here.
- **Sensors:** read hardware-scoped names and the original code, edit a local alias directly, or manage saved aliases. Clear an alias to restore the supplied name. Community names do not prove physical core or component identity; unknown sensors keep a generic kind and original code.
- **Notifications:** choose a value, condition, readable limit/unit and waiting time. Sensor choices use names. Advanced controls expose ranges, recovery and repeat behavior. Add/update the draft, then Apply. State-change controls and their individual wait times live here too.
- **Shortcuts:** configure optional native global combinations, with conflicts reported after Apply.
- **Permissions:** explicit notifications, calendar, Wi-Fi identity and launch-at-login actions. These choices are independent of forecast/map consent.

Network menu numbers use reserved right-aligned columns, with download and upload stacked. Graphs reuse existing history. Native gauges distinguish a valid zero from unavailable data. Provider-reported weather codes or recognized NWS icon metadata choose condition icons; a missing day/night flag never implies daytime. Grouped modules retain individual mouse, keyboard and accessibility actions.

This presentation is a development preview. Synthetic controls and drawing tests do not establish real rendering or the memory target; see [release acceptance](ACCEPTANCE.md).
