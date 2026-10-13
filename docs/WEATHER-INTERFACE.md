# Weather interface

Updated 2026-10-13.

Aerie's native weather panel uses the same 416 × 600 point window as the system detail panels. Its 530 point scroll viewport contains current conditions, seven complete hourly columns, and five complete outlook rows with a complete synthetic forecast. With one point-alert banner, four outlooks remain completely visible and the next can be reached by scrolling. Additional alerts receive priority and can push more outlooks below the fold. The hourly strip reserves room for always-visible native scrollbars so time labels and temperatures stay readable. More cached hours remain available by horizontal scrolling, and additional outlooks by vertical scrolling.

The current-condition card shows rounded temperatures and six paired metrics. Labels and daily minimum temperatures use secondary native text colors; current values and daily maximum temperatures have stronger contrast. Sunshine, precipitation and night symbols use restrained native colors. Unreported values display an em dash, with explicit unavailable-field explanations in accessible labels and details.

Selecting the current card opens observation precision, station and update metadata, provider notes, timezone information, alert-fetch metadata and source attribution. Selecting an hour opens all available cached fields, including precipitation/gust timing. Selecting an outlook opens its exact source periods or daily extrema, solar times and available UV information. Opening these details makes no new forecast request.

Daily model forecasts display **Low / High**. Issued day/night forecasts display **D day / N night**, preserving each period's valid interval and temperature. An absent or expired day/night period displays an em dash. The compact probability is the maximum reported period probability for an issued-period group, or the provider's daily maximum probability for a daily forecast. It is not a combined daily precipitation probability. Complete period details remain available in the outlook detail window.

Provider-reported daylight and recognized condition categories select native system symbols. Hourly daylight is inferred from sunrise/sunset only when those boundaries were supplied for the forecast day. Unknown daylight remains unknown. A daily summary with no daylight metadata uses a neutral condition symbol.

Forecast status and the fifteen-minute refresh cadence remain visible but secondary. Source attribution appears in the current card, with complete licensing/source text in details. Point alerts appear ahead of the hourly strip. Missing-data and cached/error states remain explicit; current dew point, UV and visibility are not invented from future hourly values.

Unchanged forecast presentations and native controls are reused between system samples. Report data, status, unit/name/forecast-window changes and exact forecast-window boundaries invalidate reuse. Dismissal, disablement and module changes release the presentation. The weather source's cadence, data coverage, consent, chosen location and provider are unchanged.

Synthetic tests verify layout, cached detail actions, accessibility, source-day boundaries, partial day/night data, missing fields, presentation reuse and teardown. CI renders native weather content in light/dark appearances with complete daily, issued-period, missing-data and alert fixtures. Those images contain synthetic data only. These are offscreen content renders; final live-window, keyboard/scrolling and resource acceptance still require the running review to finish and a coordinated build rollout. No memory improvement is claimed from fixture tests.
