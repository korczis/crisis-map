defmodule CrisisMapWeb.ApiTest do
  @moduledoc """
  The HTTP, OpenAPI and MCP surfaces, tested as what they are: three renderings
  of one registry. What is asserted here is mostly agreement — that the same
  call produces the same answer whichever door it came through.
  """
  use CrisisMapWeb.ConnCase, async: true

  import CrisisMap.EventsFixtures

  alias CrisisMap.Capabilities

  describe "the generated REST routes" do
    setup do
      %{
        praha: event_fixture(%{external_id: "praha", type: "fire", location_text: "Praha", at: {50.0755, 14.4378}}),
        ostrava: event_fixture(%{external_id: "ostrava", type: "fire", location_text: "Ostrava", at: {49.8209, 18.2625}}),
        nowhere: event_fixture(%{external_id: "nowhere", type: "flood", location_text: "Neznámé místečko u lesa"})
      }
    end

    test "list events", %{conn: conn} do
      body = conn |> get(~p"/api/v1/events") |> json_response(200)

      assert body["capability"] == "events.list"
      assert length(body["data"]) == 3
    end

    test "filter by type through the same schema the CLI uses", %{conn: conn} do
      body = conn |> get(~p"/api/v1/events?type=flood") |> json_response(200)

      assert [%{"external_id" => "nowhere"}] = body["data"]
    end

    test "an unlocated event is returned with no coordinates and a reason", %{conn: conn} do
      body = conn |> get(~p"/api/v1/events?type=flood") |> json_response(200)

      assert [event] = body["data"]
      assert event["latitude"] == nil
      assert event["located"] == false
      assert event["location_text"] == "Neznámé místečko u lesa"
      assert event["geocoding"]["status"] == "not_found"
    end

    test "fetch one event by external id", %{conn: conn} do
      body = conn |> get(~p"/api/v1/events/praha") |> json_response(200)

      assert body["data"]["title"] == "Dopravní nehoda"
      assert body["data"]["latitude"] == 50.0755
    end

    test "a missing event is a 404 with a reason, not a crash", %{conn: conn} do
      body = conn |> get(~p"/api/v1/events/nope") |> json_response(404)

      assert body["error"]["kind"] == "not_found"
    end

    test "the spatial route does not collide with the :id route", %{conn: conn} do
      body = conn |> get(~p"/api/v1/events/near?lat=50.0755&lon=14.4378&radius_km=50") |> json_response(200)

      assert body["capability"] == "events.near"
      assert [%{"external_id" => "praha", "distance_m" => distance}] = body["data"]
      assert distance < 1.0
    end

    test "a malformed parameter is a 400 with the capability's own message", %{conn: conn} do
      body = conn |> get(~p"/api/v1/events/near?lat=north&lon=14.4&radius_km=50") |> json_response(400)

      assert body["error"]["kind"] == "bad_request"
      assert body["error"]["message"] =~ "is not a number"
    end

    test "stats, catalog and health answer over HTTP too", %{conn: conn} do
      assert conn |> get(~p"/api/v1/events/stats") |> json_response(200) |> get_in(["data", "total"]) == 3
      assert conn |> get(~p"/api/v1/catalog/event-types") |> json_response(200) |> Map.fetch!("data") |> length() == 6
      assert conn |> get(~p"/api/v1/health") |> json_response(200) |> get_in(["data", "database", "reachable"])
    end

    test "the registry describes itself over HTTP", %{conn: conn} do
      body = conn |> get(~p"/api/v1/capabilities") |> json_response(200)

      assert Enum.map(body["data"], & &1["name"]) == Capabilities.names()
    end
  end

  describe "the OpenAPI document" do
    test "is inferred and describes every route that exists", %{conn: conn} do
      spec = conn |> get(~p"/openapi.json") |> json_response(200)

      assert spec["openapi"] == "3.1.0"
      assert spec["info"]["title"] == "Crisis Map"

      # Phoenix path parameters are rendered the way OpenAPI writes them.
      assert Map.has_key?(spec["paths"], "/api/v1/events/{id}")
      assert get_in(spec, ["paths", "/api/v1/events", "get", "operationId"]) == "events.list"
      assert get_in(spec, ["paths", "/api/v1/ingest/import", "post", "operationId"]) == "ingest.import"
    end

    test "carries each capability's declared examples", %{conn: conn} do
      spec = conn |> get(~p"/openapi.json") |> json_response(200)

      examples = get_in(spec, ["paths", "/api/v1/geocoding/lookup", "get", "responses", "200", "content", "application/json", "examples"])

      assert map_size(examples) == 2
    end

    test "Swagger UI is served over it", %{conn: conn} do
      html = conn |> get(~p"/swagger") |> html_response(200)

      assert html =~ "swagger-ui"
      assert html =~ "/openapi.json"
    end
  end

  describe "the MCP server" do
    test "announces itself", %{conn: conn} do
      result = rpc(conn, "initialize")

      assert result["serverInfo"]["name"] == "crisis_map"
      assert result["capabilities"]["tools"] == %{}
    end

    test "lists one tool per capability, with schemas and read-only hints", %{conn: conn} do
      tools = rpc(conn, "tools/list")["tools"]

      assert length(tools) == length(Capabilities.all())
      assert Enum.map(tools, & &1["name"]) |> Enum.member?("events_near")

      import_tool = Enum.find(tools, &(&1["name"] == "ingest_import"))
      refute import_tool["annotations"]["readOnlyHint"]

      list_tool = Enum.find(tools, &(&1["name"] == "events_list"))
      assert list_tool["annotations"]["readOnlyHint"]
      assert list_tool["inputSchema"]["properties"]["type"]["type"] == "string"
    end

    test "calls a tool and answers with the same data the API returns", %{conn: conn} do
      event_fixture(%{external_id: "praha", at: {50.0755, 14.4378}})

      result = rpc(conn, "tools/call", %{"name" => "events_list", "arguments" => %{}})

      refute result["isError"]
      assert [%{"type" => "text", "text" => text}] = result["content"]
      assert [event] = Jason.decode!(text)
      assert event["external_id"] == "praha"
    end

    test "a validation failure is an error result, not a protocol error", %{conn: conn} do
      result = rpc(conn, "tools/call", %{"name" => "events_get", "arguments" => %{}})

      assert result["isError"]
      assert [%{"text" => "missing required parameter id"}] = result["content"]
    end

    test "an unknown tool is a JSON-RPC error", %{conn: conn} do
      body =
        conn
        |> post("/mcp", %{"jsonrpc" => "2.0", "id" => 9, "method" => "tools/call", "params" => %{"name" => "nope"}})
        |> json_response(200)

      assert body["error"]["code"] == -32602
    end

    test "an unknown method is a JSON-RPC error", %{conn: conn} do
      body =
        conn
        |> post("/mcp", %{"jsonrpc" => "2.0", "id" => 9, "method" => "resources/list"})
        |> json_response(200)

      assert body["error"]["code"] == -32601
    end
  end

  defp rpc(conn, method, params \\ %{}) do
    conn
    |> post("/mcp", %{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params})
    |> json_response(200)
    |> Map.fetch!("result")
  end
end
