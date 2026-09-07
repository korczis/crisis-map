defmodule CrisisMapWeb.ApiDocsController do
  @moduledoc """
  Serves the inferred OpenAPI document and a Swagger UI over it.

  The UI is the standard distribution loaded from a CDN and pointed at
  `/openapi.json`; there is no checked-in copy of a specification for it to
  drift away from.
  """
  use CrisisMapWeb, :controller

  alias CrisisMap.OpenAPI

  def spec(conn, _params), do: json(conn, OpenAPI.spec())

  def swagger(conn, _params) do
    html(conn, """
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
          window.onload = () => SwaggerUIBundle({url: "/openapi.json", dom_id: "#swagger"});
        </script>
      </body>
    </html>
    """)
  end
end
