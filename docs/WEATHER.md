# Weather sources

Updated 2026-10-11. Weather is off by default. Development and CI use synthetic forecasts; neither automatically requests the user's location.

## Open-Meteo forecast adapter

[Open-Meteo terms](https://open-meteo.com/en/terms) permit the free hosted service for personal/noncommercial use, within the documented request limits. The app refreshes at most every 15 minutes for one chosen location. The provider abstraction allows a different compliant backend later. Calling the REST API does not incorporate its server source code.

Data attribution is displayed as Open-Meteo with a link; forecast data is licensed under CC BY 4.0. Current conditions are model-derived estimates, rather than local station observations. Quality and resolution vary by region, model, terrain, and forecast lead time. The service offers regional models including NOAA HRRR in supported US coverage; selecting a model is a later option.

Opt-in discloses IP and coordinate transmission and coordinate-bearing troubleshooting logs which the provider may retain up to 90 days. Manual coordinates are rounded to two decimal places. No credentials, geocoding query, or precise device location is required.

## Detailed maps milestone

The intended window loads only on demand and releases requests, animation timers, raster frames, and rendering state when closed. Idle/background footprint keeps the strict all-process budget. Active map use may have reasonable temporary headroom; measure its peak and verify prompt return close to baseline after close, including repeated open/close cycles. A bounded frame cache and timestamps/legends are required.

| Layer | Source direction | Coverage and distinction |
| --- | --- | --- |
| Observed radar and storm tracking | [NOAA radar GIS](https://opengeo.ncep.noaa.gov/geoserver/www/index.html), MRMS and supported station products | US products; observed reflectivity is separate from forecast precipitation. Storm tracks need a verified track product or clearly labeled derived analysis. |
| Satellite | [NOAA nowCOAST](https://www.nauticalcharts.noaa.gov/learn/nowcoast.html) time-enabled WMS | Validate current service layers, bands, timestamps, and coverage. |
| Official alerts | [NWS API](https://www.weather.gov/documentation/services-web-api) and NOAA warning GIS | US official alerts; source and issuance/expiry times must be retained. |
| Temperature, wind, rain, snow forecasts | [NWS CloudGIS/NDFD](https://www.weather.gov/gis/cloudgiswebservices) | Forecast valid time and accumulation period must be explicit. Services and layer names still require implementation validation. |

NOAA public data is available without paid credentials, but basemap licensing and per-layer attribution must be verified before use. Detailed map APIs are not yet integrated; no display claims are made for missing layers. No heavy always-resident web view is planned.
