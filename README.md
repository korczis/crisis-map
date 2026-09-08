# Crisis Map

A small vertical slice: incident reports in, points on a map out.

```
source record → normalise → persist → geocode → PostGIS → LiveView → operator
```

Everything else in this repository exists to keep that path honest — one
registry of operations, projected onto every surface, with gates that fail
when a projection or a document drifts away from it.

## Run it

The application needs PostgreSQL with PostGIS and a local Nominatim. Both come
from the academy geo stack (`hzs_radar/docker-compose.geo.yml`): PostGIS on
`localhost:55432`, Nominatim on `localhost:8080`. Override with `GEO_DB_HOST`,
`GEO_DB_PORT`, `GEO_DB_USER`, `GEO_DB_PASSWORD` and `NOMINATIM_URL`.

```bash
mix setup                 # deps, database, migrations, assets
mix crisis_map.import     # load priv/data/events.json
mix phx.server            # http://localhost:4000
```

| Page | What it is |
|---|---|
| `/` | the map, the event list, the detail panel, the filters |
| `/cockpit` | every capability, described and runnable in the browser |
| `/swagger` | Swagger UI over the inferred OpenAPI document |
| `/openapi.json` | the OpenAPI document itself |
| `/mcp` | MCP over HTTP JSON-RPC (`initialize`, `tools/list`, `tools/call`) |

```bash
mix crisis_map.capabilities                # what this system can do
mix crisis_map.run events.stats            # any capability, from the shell
mix crisis_map.run events.near --lat 50.0755 --lon 14.4378 --radius-km 50
mix crisis_map.bench                       # measure every capability
mix crisis_map.docs                        # regenerate docs/
mix crisis_map.site                        # build the published site
mix gates                                  # everything CI enforces
```

## Layers

| Layer | Where | What it may know |
|---|---|---|
| Infrastructure | `CrisisMap.Repo`, `CrisisMap.Geocoding.Nominatim`, `priv/repo/migrations`, `CrisisMap.Ingest.Source` | HTTP, SQL, file formats |
| Domain | `CrisisMap.Events`, `CrisisMap.Events.Event`, `CrisisMap.Ingest`, `CrisisMap.Catalog`, `CrisisMap.Geocoding` | events, positions, identity, the rules |
| Application | `CrisisMap.Capabilities` and its providers | which operations exist and what they mean |
| Presentation | `CrisisMapWeb.*`, `Mix.Tasks.CrisisMap.*`, `CrisisMap.Docs`, `CrisisMap.Site` | how an operation is rendered |

The dependency arrow only ever points down. The domain does not know that a
LiveView exists; the LiveView does not write a query; the geocoder is reached
through a boundary the domain owns, and swapped by configuration, which is
what makes "the geocoder is down" a testable state rather than a bad day.

## Decisions

**Identity is the source's `external_id`, with a unique index.** Two records
are the same event when the source says so. Nothing else is stable enough:
titles get corrected, times get refined, and two genuinely different fires can
share a place and a minute. Import is an upsert on that key, so the same file
imported twice yields the same rows — proven in `test/crisis_map/ingest_test.exs`.

**Position is `geography(Point,4326)`, not two float columns.** Two columns
can store a position but cannot answer a question about one: "within 50 km"
in plain SQL is either wrong (degrees are not kilometres, and a degree of
longitude in Bohemia is ~64% of a degree of latitude) or a hand-rolled
haversine that no index can help. With geography, `ST_DWithin` measures metres
on the spheroid and the GiST index answers it. `geography` over `geometry`
because every distance here is a real-world distance, and geography is metric
by definition rather than by whichever projection someone remembers to apply.

**An unknown position is `NULL` plus a status that says why.** `pending`,
`ok`, `not_found`, `skipped`, `error` — declared in `CrisisMap.Catalog`, and
the changeset enforces the pairing, so a row can never claim a known position
without a point or an unknown one with a point. No sentinel coordinates, no
0/0, no centroid of the country. An event whose place nobody knows stays in
the database, keeps its `location_text`, and simply does not appear on the map.

**Source and derived fields are separated on purpose.** `external_id`, `title`,
`description`, `type`, `location_text` and `occurred_at` are what the source
said (normalised: trimmed, parsed, type mapped onto the catalog). `geom`,
`geocoding_status`, `geocoded_display_name`, `geocoding_candidates`,
`geocoding_confidence` and `geocoded_at` are what this system worked out, and
each carries the evidence for it — including how many candidates the geocoder
offered, so an ambiguous name stays visibly ambiguous.

**One registry, many projections.** Each operation is declared once in a
capability provider with its documentation, parameter schema and examples. The
CLI, the REST routes, the OpenAPI document, the MCP tools, the cockpit, the
reference documentation, the benchmark inventory and the conformance suite are
all generated from that declaration. Adding an operation is one edit; there is
no second place that could disagree. Providers are configurable
(`config :crisis_map, :capability_providers`), so an operation can be
contributed from outside this application.

## Failure handling

| Situation | What happens |
|---|---|
| The same record arrives twice | One row. The second pass updates it. |
| Nominatim knows the place | `geom` set, `geocoding_status: "ok"`, candidates and score stored. |
| Nominatim knows nothing | `geocoding_status: "not_found"`, `geom` NULL, `location_text` kept. The import continues. |
| Nominatim is down or stalls | Five-second receive timeout, two-second connect timeout, no retries. That record gets `geocoding_status: "error"` and is reported; every other record still imports. A re-import retries it. |
| A record cannot be parsed | Counted as `invalid`, reported with its identifier, and the rest of the file still imports. |
| A position disappears on re-geocoding | Cleared, not left stale. |

Nothing invents a coordinate, and nothing lets one bad record end a run.

## Documentation

| Document | Generated from |
|---|---|
| [docs/CAPABILITIES.md](docs/CAPABILITIES.md) | the capability registry |
| [docs/CATALOG.md](docs/CATALOG.md) | `CrisisMap.Catalog` |
| [docs/DOCTRINE.md](docs/DOCTRINE.md) | written by hand; every rule names the test that enforces it |
| the published site | the registry, built by CI from the commit it publishes |

`mix crisis_map.docs --check` fails when a generated document is stale, and CI
runs it, so documentation cannot quietly stop being true.
