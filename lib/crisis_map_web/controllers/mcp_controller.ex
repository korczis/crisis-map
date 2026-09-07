defmodule CrisisMapWeb.MCPController do
  @moduledoc """
  The MCP projection of the capability registry.

  A minimal Model Context Protocol server over HTTP JSON-RPC: `initialize`,
  `tools/list` and `tools/call`. The tool list is generated from the registry,
  including each tool's description and JSON Schema, so an assistant sees
  exactly the operations the CLI and the API expose, described in the same
  words, and a capability can never be reachable from one surface but not the
  others.
  """
  use CrisisMapWeb, :controller

  alias CrisisMap.Capabilities
  alias CrisisMap.Capability

  @protocol_version "2025-06-18"

  def rpc(conn, %{"method" => method} = request) do
    id = Map.get(request, "id")
    params = Map.get(request, "params", %{})

    case handle(method, params) do
      :notification -> send_resp(conn, 202, "")
      {:ok, result} -> json(conn, %{jsonrpc: "2.0", id: id, result: result})
      {:error, code, message} -> json(conn, %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}})
    end
  end

  def rpc(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{jsonrpc: "2.0", id: nil, error: %{code: -32600, message: "invalid request"}})
  end

  defp handle("initialize", _params) do
    {:ok,
     %{
       protocolVersion: @protocol_version,
       capabilities: %{tools: %{}},
       serverInfo: %{name: "crisis_map", version: version()}
     }}
  end

  defp handle("notifications/initialized", _params), do: :notification

  defp handle("tools/list", _params) do
    {:ok, %{tools: Enum.map(Capabilities.all(), &tool/1)}}
  end

  defp handle("tools/call", %{"name" => name} = params) do
    arguments = Map.get(params, "arguments", %{})

    case capability_for_tool(name) do
      nil ->
        {:error, -32602, "unknown tool: #{name}"}

      capability ->
        case Capabilities.dispatch(capability.name, arguments) do
          {:ok, data} ->
            {:ok, %{content: [%{type: "text", text: Jason.encode!(data, pretty: true)}], isError: false}}

          {:error, {_kind, message}} ->
            {:ok, %{content: [%{type: "text", text: to_string(message)}], isError: true}}

          {:error, reason} ->
            {:ok, %{content: [%{type: "text", text: inspect(reason)}], isError: true}}
        end
    end
  end

  defp handle("tools/call", _params), do: {:error, -32602, "missing tool name"}
  defp handle(method, _params), do: {:error, -32601, "method not found: #{method}"}

  defp tool(%Capability{} = capability) do
    %{
      name: Capability.tool_name(capability),
      description: "#{capability.summary}. #{String.trim(capability.description)}",
      inputSchema: Capability.json_schema(capability),
      annotations: %{
        readOnlyHint: not capability.mutating,
        title: capability.summary
      }
    }
  end

  defp capability_for_tool(tool_name) do
    Enum.find(Capabilities.all(), &(Capability.tool_name(&1) == tool_name))
  end

  defp version, do: to_string(Application.spec(:crisis_map, :vsn) || "0.0.0")
end
