defmodule CrisisMap.Site do
  @moduledoc """
  The published site, generated from the registry.

  What GitHub Pages serves is not a hand-written description of the project:
  it is this renderer over `CrisisMap.Capabilities`, `CrisisMap.Catalog` and
  `CrisisMap.OpenAPI`, so the published pages and the running system are the
  same declaration twice. The Swagger page on the site reads the same OpenAPI
  document the application serves at `/openapi.json`.
  """

  alias CrisisMap.Capabilities
  alias CrisisMap.Capability
  alias CrisisMap.Catalog
  alias CrisisMap.OpenAPI

  @doc "Every file of the site, as a map of relative path to content."
  @spec files() :: %{String.t() => iodata()}
  def files do
    %{
      "index.html" => index(),
      "capabilities.html" => capabilities_page(),
      "catalog.html" => catalog_page(),
      "swagger.html" => swagger_page(),
      "openapi.json" => Jason.encode_to_iodata!(OpenAPI.spec(), pretty: true)
    }
  end

  defp index do
    page("Crisis Map", """
    <p class="lead">
      Incident reports, normalised, geocoded against a local Nominatim and stored
      as PostGIS geography. One vertical path from a raw record to a point on a
      map, and one registry from which every surface is generated.
    </p>

    <h2>The path</h2>
    <pre class="flow">#{Enum.join(["source record", "  → normalise      (CrisisMap.Ingest.Normalizer)", "  → persist        (CrisisMap.Events, idempotent on external_id)", "  → geocode        (CrisisMap.Geocoding, adapter: Nominatim)", "  → store position (geography(Point,4326), or NULL with a reason)", "  → query          (PostGIS ST_DWithin / ST_Distance)", "  → LiveView       (map, list, detail, filters)"],
    "\n")}</pre>

    <h2>Surfaces</h2>
    <p>
      #{length(Capabilities.all())} capabilities are declared once and projected onto
      each of these. None of them can offer an operation the others do not.
    </p>
    <table>
      <tr><th>Surface</th><th>Where</th></tr>
      <tr><td>Command line</td><td><code>mix crisis_map.run &lt;capability&gt;</code></td></tr>
      <tr><td>JSON API</td><td><code>/api/v1/…</code></td></tr>
      <tr><td>OpenAPI</td><td><a href="openapi.json">openapi.json</a>, <a href="swagger.html">Swagger UI</a></td></tr>
      <tr><td>MCP</td><td><code>POST /mcp</code> (JSON-RPC: initialize, tools/list, tools/call)</td></tr>
      <tr><td>Cockpit</td><td><code>/cockpit</code></td></tr>
      <tr><td>Documentation</td><td><a href="capabilities.html">capabilities</a>, <a href="catalog.html">catalog</a></td></tr>
    </table>

    <h2>Provenance</h2>
    <p>
      Every stored event separates what the source said from what this system
      worked out. The source fields are normalised, never invented; the derived
      fields always carry the evidence that produced them, and an unknown
      position is <code>NULL</code> with a status that says why — never a
      guessed coordinate.
    </p>
    """)
  end

  defp capabilities_page do
    page("Capabilities", """
    <p class="lead">#{length(Capabilities.all())} operations, each declared once.</p>
    #{Enum.map_join(Capabilities.all(), "\n", &capability_block/1)}
    """)
  end

  defp capability_block(%Capability{} = capability) do
    """
    <section>
      <h2 id="#{capability.name}"><code>#{capability.name}</code></h2>
      <p>#{escape(capability.summary)}</p>
      <p>#{escape(String.trim(capability.description))}</p>
      <table>
        <tr><th>HTTP</th><td><code>#{Capability.http(capability)}</code></td></tr>
        <tr><th>CLI</th><td><code>#{escape(Capability.cli(capability))}</code></td></tr>
        <tr><th>MCP tool</th><td><code>#{Capability.tool_name(capability)}</code></td></tr>
        <tr><th>Returns</th><td>#{escape(capability.returns)}</td></tr>
      </table>
      #{params_table(capability)}
    </section>
    """
  end

  defp params_table(%Capability{params: []}), do: "<p><em>No parameters.</em></p>"

  defp params_table(%Capability{params: params}) do
    """
    <table>
      <tr><th>Parameter</th><th>Type</th><th>Required</th><th>Description</th></tr>
      #{Enum.map_join(params, "\n", fn param -> "<tr><td><code>#{param.name}</code></td><td><code>#{param.type}</code></td><td>#{if Map.get(param, :required, false), do: "yes", else: "no"}</td><td>#{escape(param.description)}</td></tr>" end)}
    </table>
    """
  end

  defp catalog_page do
    page("Catalog", """
    <p class="lead">The vocabulary every surface shares.</p>

    <h2>Event types</h2>
    <table>
      <tr><th>Id</th><th>Label</th><th>Colour</th><th>Meaning</th></tr>
      #{Enum.map_join(Catalog.event_types(), "\n", fn type -> "<tr><td><code>#{type.id}</code></td><td>#{escape(type.label)}</td><td><span class=\"swatch\" style=\"background:#{type.color}\"></span> <code>#{type.color}</code></td><td>#{escape(type.description)}</td></tr>" end)}
    </table>

    <h2>Geocoding statuses</h2>
    <table>
      <tr><th>Id</th><th>Coordinates known</th><th>Meaning</th></tr>
      #{Enum.map_join(Catalog.geocoding_statuses(), "\n", fn status -> "<tr><td><code>#{status.id}</code></td><td>#{if status.coordinates_known, do: "yes", else: "no"}</td><td>#{escape(status.description)}</td></tr>" end)}
    </table>

    <h2>Reference points</h2>
    <table>
      <tr><th>Id</th><th>Label</th><th>Latitude</th><th>Longitude</th></tr>
      #{Enum.map_join(Catalog.reference_points(), "\n", fn point -> "<tr><td><code>#{point.id}</code></td><td>#{escape(point.label)}</td><td>#{point.lat}</td><td>#{point.lon}</td></tr>" end)}
    </table>
    """)
  end

  defp swagger_page do
    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Crisis Map API</title>
        <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5.17.14/swagger-ui.css" />
      </head>
      <body style="margin:0">
        <div id="swagger"></div>
        <script src="https://unpkg.com/swagger-ui-dist@5.17.14/swagger-ui-bundle.js"></script>
        <script>
          window.onload = () => SwaggerUIBundle({url: "./openapi.json", dom_id: "#swagger"});
        </script>
      </body>
    </html>
    """
  end

  defp page(title, body) do
    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>#{title} · Crisis Map</title>
        <style>
          :root { color-scheme: light dark; }
          body { margin: 0 auto; max-width: 52rem; padding: 2rem 1rem 6rem;
                 font: 15px/1.6 ui-sans-serif, system-ui, sans-serif; }
          nav { display: flex; gap: 1rem; margin-bottom: 2rem; font-size: 14px; }
          h1 { font-size: 1.6rem; } h2 { font-size: 1.15rem; margin-top: 2rem; }
          .lead { font-size: 1.05rem; opacity: .85; }
          table { border-collapse: collapse; width: 100%; margin: 1rem 0; display: block; overflow-x: auto; }
          th, td { text-align: left; padding: .4rem .6rem; border-bottom: 1px solid #8883; vertical-align: top; }
          code { font-family: ui-monospace, monospace; font-size: .9em; }
          pre.flow { background: #8881; padding: 1rem; border-radius: .4rem; overflow-x: auto; }
          section { border-top: 1px solid #8883; padding-top: .5rem; }
          .swatch { display: inline-block; width: .8em; height: .8em; border-radius: 50%; vertical-align: middle; }
          footer { margin-top: 4rem; font-size: 13px; opacity: .7; }
        </style>
      </head>
      <body>
        <nav>
          <a href="index.html">Overview</a>
          <a href="capabilities.html">Capabilities</a>
          <a href="catalog.html">Catalog</a>
          <a href="swagger.html">API</a>
        </nav>
        <h1>#{title}</h1>
        #{body}
        <footer>Generated by <code>mix crisis_map.site</code> from the capability registry.</footer>
      </body>
    </html>
    """
  end

  defp escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
