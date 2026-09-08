defmodule CrisisMap.Capabilities.Builtin do
  @moduledoc """
  The capabilities this application ships with.

  This module is a *provider*: `CrisisMap.Capabilities` asks it, and every
  other configured provider, for their declarations. Splitting it out is what
  makes the registry extensible from outside — an extension declares its own
  operations in its own module and they appear on every surface, rather than
  everything having to be added to one growing list here.
  """

  @behaviour CrisisMap.Capabilities.Provider

  alias CrisisMap.Capability
  alias CrisisMap.Catalog
  alias CrisisMap.Events
  alias CrisisMap.Geocoding
  alias CrisisMap.Ingest
  alias CrisisMap.Repo
  alias CrisisMap.Views

  @type_param %{
    name: :type,
    type: :string,
    description: "Restrict to one catalog event type. Omit or pass `all` for every type.",
    example: "fire"
  }

  @impl true
  @spec capabilities() :: [Capability.t()]
  def capabilities do
    [
      %Capability{
        name: "events.list",
        summary: "List stored events",
        description: """
        Returns stored events, newest first. Filters are combinable: `type`
        restricts to one catalog type, `located` keeps only events whose
        position is known, and `limit` caps the number of rows. Events whose
        position could not be resolved are returned like any other — they
        simply carry no coordinates.
        """,
        tags: ["events"],
        http: %{method: :get, path: "/api/v1/events"},
        returns: "An array of event objects.",
        params: [
          @type_param,
          %{
            name: :located,
            type: :boolean,
            description: "Keep only events with known coordinates.",
            example: true
          },
          %{name: :limit, type: :integer, description: "Maximum number of rows.", example: 50}
        ],
        examples: [
          %{description: "Every stored event", params: %{}},
          %{
            description: "Only fires that can be drawn on the map",
            params: %{type: "fire", located: true}
          }
        ],
        handler: fn params ->
          {:ok, params |> Events.list_events() |> Views.events()}
        end
      },
      %Capability{
        name: "events.get",
        summary: "Fetch one event",
        description: """
        Returns one event by its database id or by the source's own
        `external_id`. Both are accepted because the two identities answer
        different questions: the database id is ours, the external id is the
        source's and is what makes the import idempotent.
        """,
        tags: ["events"],
        http: %{method: :get, path: "/api/v1/events/:id"},
        returns: "One event object.",
        params: [
          %{
            name: :id,
            type: :string,
            required: true,
            description: "Database id or source external_id.",
            example: "event-101"
          }
        ],
        examples: [%{description: "By source identifier", params: %{id: "event-101"}}],
        handler: fn %{id: id} ->
          event =
            case Integer.parse(id) do
              {numeric_id, ""} -> Events.get_event(numeric_id)
              _ -> Events.get_event_by_external_id(id)
            end

          case event do
            nil -> {:error, {:not_found, "no event with id #{id}"}}
            event -> {:ok, Views.event(event)}
          end
        end
      },
      %Capability{
        name: "events.near",
        summary: "Events within a radius of a point",
        description: """
        The spatial query proper. Answers "what happened within X km of here"
        using PostGIS `ST_DWithin` on the geography column, which measures on
        the spheroid in metres and is answered from the GiST index rather than
        by scanning the table. Every returned event also carries its
        `distance_m`, computed by `ST_Distance` in the same query.
        """,
        tags: ["events", "spatial"],
        http: %{method: :get, path: "/api/v1/events/near"},
        returns: "An array of event objects, each with `distance_m` set.",
        params: [
          %{
            name: :lat,
            type: :float,
            required: true,
            description: "Latitude of the centre.",
            example: 50.0755
          },
          %{
            name: :lon,
            type: :float,
            required: true,
            description: "Longitude of the centre.",
            example: 14.4378
          },
          %{
            name: :radius_km,
            type: :float,
            required: true,
            description: "Search radius in kilometres.",
            example: 50.0
          },
          @type_param
        ],
        examples: [
          %{
            description: "Everything within 50 km of Prague",
            params: %{lat: 50.0755, lon: 14.4378, radius_km: 50}
          }
        ],
        handler: fn params ->
          within = %{lat: params.lat, lon: params.lon, radius_km: params.radius_km}

          events =
            params
            |> Map.take([:type])
            |> Map.put(:within, within)
            |> Events.list_events()
            |> Enum.sort_by(& &1.distance_m)

          {:ok, Views.events(events)}
        end
      },
      %Capability{
        name: "events.stats",
        summary: "Counts by type and by geocoding status",
        description: """
        The shape of the stored data at a glance: how many events of each
        catalog type, and how many positions are known, unknown, not found or
        failed. This is the number the operator looks at after an import.
        """,
        tags: ["events"],
        http: %{method: :get, path: "/api/v1/events/stats"},
        returns: "An object with `total`, `by_type` and `by_geocoding_status`.",
        params: [],
        examples: [%{description: "Current counts", params: %{}}],
        handler: fn _params ->
          {:ok,
           %{
             total: Events.count_events(),
             by_type: Events.count_by_type(),
             by_geocoding_status: Events.count_by_geocoding_status()
           }}
        end
      },
      %Capability{
        name: "catalog.event_types",
        summary: "The declared event types",
        description: """
        The canonical vocabulary of event types, with the label and map colour
        each one is drawn with. Every other surface reads this list rather than
        keeping its own copy, which is why a new type appears in the filter,
        the map legend and the API documentation at once.
        """,
        tags: ["catalog"],
        http: %{method: :get, path: "/api/v1/catalog/event-types"},
        returns: "An array of event type objects.",
        params: [],
        examples: [%{description: "The whole vocabulary", params: %{}}],
        handler: fn _params -> {:ok, Catalog.event_types()} end
      },
      %Capability{
        name: "catalog.geocoding_statuses",
        summary: "The declared geocoding statuses",
        description: """
        Every state a position can be in, and whether that state means the
        coordinates are known. The schema enforces the pairing: a status that
        claims coordinates exist cannot be stored without a point, and one that
        claims they do not cannot be stored with one.
        """,
        tags: ["catalog"],
        http: %{method: :get, path: "/api/v1/catalog/geocoding-statuses"},
        returns: "An array of geocoding status objects.",
        params: [],
        examples: [%{description: "Every status", params: %{}}],
        handler: fn _params -> {:ok, Catalog.geocoding_statuses()} end
      },
      %Capability{
        name: "geocoding.lookup",
        summary: "Resolve a place name",
        description: """
        Forward geocoding through the configured geocoder, without storing
        anything. The answer carries `candidates` — how many places the
        geocoder found plausible — and `confidence`, its ranking score for the
        one returned, so an ambiguous name is visibly ambiguous.

        A place the geocoder does not know is `not_found`, which is an answer,
        not a failure. A geocoder that cannot be reached is an `error`.
        """,
        tags: ["geocoding"],
        http: %{method: :get, path: "/api/v1/geocoding/lookup"},
        returns:
          "An object with `status` and, when found, `latitude`, `longitude`, `candidates` and `confidence`.",
        params: [
          %{
            name: :query,
            type: :string,
            required: true,
            description: "Place name to resolve.",
            example: "Beroun"
          }
        ],
        examples: [
          %{description: "A place the local dataset knows", params: %{query: "Beroun"}},
          %{description: "A place nobody knows", params: %{query: "Neznámé místečko u lesa"}}
        ],
        handler: fn %{query: query} ->
          case Geocoding.geocode(query) do
            {:ok, result} ->
              {:ok,
               %{
                 status: "ok",
                 query: query,
                 latitude: result.lat,
                 longitude: result.lon,
                 display_name: result.display_name,
                 candidates: result.candidates,
                 confidence: result.confidence
               }}

            {:error, :not_found} ->
              {:ok, %{status: "not_found", query: query}}

            {:error, reason} ->
              {:ok, %{status: "error", query: query, reason: inspect(reason)}}
          end
        end
      },
      %Capability{
        name: "geocoding.status",
        summary: "Health of the geocoder",
        description: """
        Asks the configured geocoder whether it is up and which adapter is in
        use. Returns a reason instead of raising when it is not, so this is
        safe to call from a status page or a monitor.
        """,
        tags: ["geocoding", "system"],
        http: %{method: :get, path: "/api/v1/geocoding/status"},
        returns: "An object describing the geocoder and its reachability.",
        params: [],
        examples: [%{description: "Is the geocoder up?", params: %{}}],
        handler: fn _params ->
          case Geocoding.status() do
            {:ok, status} ->
              {:ok, Map.put(status, :reachable, true)}

            {:error, reason} ->
              {:ok,
               %{adapter: inspect(Geocoding.adapter()), reachable: false, reason: inspect(reason)}}
          end
        end
      },
      %Capability{
        name: "ingest.import",
        summary: "Import the dataset",
        description: """
        Runs the ingest pipeline over a JSON dataset: normalise, upsert on
        `external_id`, geocode what needs geocoding, store the outcome.

        Running it twice is safe and is the point: the second run updates the
        same rows and reuses positions that are already resolved, so the report
        shows updates and reuses rather than inserts. Pass `regeocode` to
        resolve positions again anyway.
        """,
        tags: ["ingest"],
        http: %{method: :post, path: "/api/v1/ingest/import"},
        returns: "The import report: counts per outcome and the errors encountered.",
        mutating: true,
        params: [
          %{
            name: :path,
            type: :string,
            description: "Dataset to read. Defaults to the bundled dataset.",
            example: "priv/data/events.json"
          },
          %{
            name: :regeocode,
            type: :boolean,
            default: false,
            description: "Resolve positions again even when they are already known."
          }
        ],
        examples: [%{description: "Import the bundled dataset", params: %{}}],
        handler: fn params ->
          opts = params |> Map.take([:path, :regeocode]) |> Enum.into([])

          case Ingest.import_file(opts) do
            {:ok, report} -> {:ok, report}
            {:error, reason} -> {:error, {:unprocessable, inspect(reason)}}
          end
        end
      },
      %Capability{
        name: "system.capabilities",
        summary: "The registry itself",
        description: """
        Lists every capability with its parameters, its route, its CLI form and
        its MCP tool name. This is the registry describing itself: the same
        list that generated the routes, the OpenAPI document and the
        documentation is readable at run time.
        """,
        tags: ["system"],
        http: %{method: :get, path: "/api/v1/capabilities"},
        returns: "An array of capability descriptions.",
        params: [],
        examples: [%{description: "Everything this system can do", params: %{}}],
        handler: fn _params ->
          {:ok, Enum.map(CrisisMap.Capabilities.all(), &CrisisMap.Capabilities.describe/1)}
        end
      },
      %Capability{
        name: "system.health",
        summary: "Health of the system",
        description: """
        One call that answers whether the parts are there: the database, the
        PostGIS extension and its version, the number of stored events and
        whether the geocoder answers.
        """,
        tags: ["system"],
        http: %{method: :get, path: "/api/v1/health"},
        returns: "An object with the database, PostGIS, event and geocoder status.",
        params: [],
        examples: [%{description: "Is everything up?", params: %{}}],
        handler: fn _params ->
          {:ok,
           %{
             database: database_health(),
             events: Events.count_events(),
             geocoder: geocoder_health()
           }}
        end
      }
    ]
  end

  defp database_health do
    case Repo.query("SELECT postgis_version()") do
      {:ok, %{rows: [[version]]}} -> %{reachable: true, postgis: version}
      {:ok, _} -> %{reachable: true, postgis: nil}
      {:error, reason} -> %{reachable: false, reason: inspect(reason)}
    end
  rescue
    exception -> %{reachable: false, reason: Exception.message(exception)}
  end

  defp geocoder_health do
    case Geocoding.status() do
      {:ok, status} ->
        Map.put(status, :reachable, true)

      {:error, reason} ->
        %{adapter: inspect(Geocoding.adapter()), reachable: false, reason: inspect(reason)}
    end
  end
end
