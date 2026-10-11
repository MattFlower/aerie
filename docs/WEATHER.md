# Weather sources

Updated 2026-10-11. Weather is off by default. Development and CI use synthetic forecasts; neither automatically requests the user's location.

## Open-Meteo forecast adapter

[Open-Meteo terms](https://open-meteo.com/en/terms) permit the free hosted service for personal/noncommercial use, within the documented request limits. The app refreshes at most every 15 minutes for one chosen location. The provider abstraction allows a different compliant backend later. Calling the REST API does not incorporate its server source code.

Data attribution is displayed as Open-Meteo with a link; forecast data is licensed under CC BY 4.0. Current conditions are model-derived estimates, rather than local station observations. Quality and resolution vary by region, model, terrain, and forecast lead time. The service offers regional models including NOAA HRRR in supported US coverage; selecting a model is a later option.

Opt-in discloses IP and coordinate transmission and coordinate-bearing troubleshooting logs which the provider may retain up to 90 days. Manual coordinates are rounded to two decimal places. No credentials, geocoding query, or precise device location is required.

## Detailed maps milestone

The native AppKit window loads only on demand and releases requests, animation timers, raster frames, and rendering state when closed. Idle/background footprint keeps the strict all-process budget. Active map use may have reasonable temporary headroom; measure its peak and verify prompt return close to baseline after close, including repeated open/close cycles. A bounded frame cache and timestamps/legends are required.

| Layer | Source direction | Coverage and distinction |
| --- | --- | --- |
| Observed radar and storm tracking | [NOAA radar GIS](https://opengeo.ncep.noaa.gov/geoserver/www/index.html), MRMS and supported station products | US products; observed reflectivity is separate from forecast precipitation. Storm tracks need a verified track product or clearly labeled derived analysis. |
| Satellite | [NOAA nowCOAST](https://www.nauticalcharts.noaa.gov/learn/nowcoast.html) time-enabled WMS | Validate current service layers, bands, timestamps, and coverage. |
| Official alerts | [NWS API](https://www.weather.gov/documentation/services-web-api) and NOAA warning GIS | US official alerts; source and issuance/expiry times must be retained. |
| Temperature, wind, rain, snow forecasts | [NWS CloudGIS/NDFD](https://www.weather.gov/gis/cloudgiswebservices) | Forecast valid time and accumulation period must be explicit. Services and layer names still require implementation validation. |

NOAA public data is available without paid credentials, but basemap licensing and per-layer attribution must be verified before use. The adapters and native controls are implemented. The manual developer integration command uses a fixed public CONUS extent; public automated tests use synthetic XML and intercepted synthetic requests. Real visual and post-close footprint validation still needs an unlocked Mac. Convective-cell tracks and per-alert issuance/expiry details remain open. No web view is used.

## Map consent, data and resource behavior

NOAA maps have a separate opt-in in Weather Settings and use the manually entered location. Forecast opt-in is independent. Opening a map sends only the selected map extent and IP to the selected NOAA/NWS service. Maps are off by default; old settings decode with maps off, and import/export disables location services. No device location, third-party basemap or API key is used.

[NWS usage terms](https://www.weather.gov/disclaimer) permit its public-domain data unless a product says otherwise, require source identification and prohibit implying endorsement. The selected NWS state-boundary service identifies its copyright/source as NOAA/NWS; no external commercial basemap is incorporated. Source attribution remains visible. Service coverage varies: US radar and NDFD, GOES regional or global satellite mosaics, and NHC tropical-cyclone tracks. Tropical past/forecast tracks are distinguished from convective-cell tracks, which remain unimplemented.

Time-enabled radar, satellite and forecast layers use advertised service times. Ancient forecast metadata entries are excluded from the current timeline. WMS 1.3 axis order is explicit. Precipitation and snow products are six-hour accumulations ending at the selected valid time, in the provider's source units. Current alert and tropical-track services without a common advertised time show fetch time explicitly. Legends come from the provider; long legends scroll without shrinking text. The tropical-track legend shows the first selected forecast-track layer; fuller per-track advisory presentation remains open.

A map window owns its ephemeral HTTP session, cancellable jobs, 120-second visible-window refresh, user-started animation, metadata and decoded raster cache. Requests are spaced by at least 750 ms, with no immediate failure retry. Playback uses at most 12 cached frames, within 16 MiB of conservative decoded RGBA cost; boundary/alert/legend images are separately bounded by image dimensions and response size. Closing cancels requests/timers and clears every view image/cache. Synthetic tests verify cancellation and cache release; this does not substitute for repeated real-window footprint checks.

The explicit development command `Aerie --map-integration-fixture` checks real service metadata, rasters and legends using a fixed public CONUS extent. It does not read user settings and is not run by public CI.
