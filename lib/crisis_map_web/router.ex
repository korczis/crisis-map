defmodule CrisisMapWeb.Router do
  use CrisisMapWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CrisisMapWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", CrisisMapWeb do
    pipe_through :browser

    live "/", MapLive, :index
    live "/cockpit", CockpitLive, :index
    get "/swagger", ApiDocsController, :swagger
  end

  scope "/", CrisisMapWeb do
    pipe_through :api

    get "/openapi.json", ApiDocsController, :spec

    # Model Context Protocol over HTTP JSON-RPC. Same registry, same handlers.
    post "/mcp", MCPController, :rpc

    # The REST surface is generated from the capability registry: one route per
    # declared capability, all of them dispatched by the same controller. There
    # is deliberately no place here to add an endpoint that the registry, the
    # OpenAPI document and the documentation do not know about.
    for capability <- CrisisMap.Capabilities.routes() do
      match capability.http.method, capability.http.path, CapabilityController, :dispatch,
        assigns: %{capability: capability.name},
        as: nil
    end
  end

  if Application.compile_env(:crisis_map, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CrisisMapWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
