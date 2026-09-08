defmodule CrisisMap.Capabilities do
  @moduledoc """
  The registry: every operation this system offers, gathered from its
  providers.

  Providers are listed under `config :crisis_map, :capability_providers` and
  each returns `CrisisMap.Capability` declarations; the built-in ones live in
  `CrisisMap.Capabilities.Builtin`. Whatever the providers declare appears —
  with its documentation, its parameter schema and its examples — in the CLI,
  the JSON API, the OpenAPI document, the MCP tool list, the cockpit, the
  generated documentation, the benchmark inventory and the conformance suite,
  without any of those being edited.

  The doctrine tests in `test/crisis_map/doctrine_test.exs` enforce that the
  declarations stay complete: a capability without a description, without an
  example, without a route or without a test is a build failure.
  """

  alias CrisisMap.Capability

  @default_providers [CrisisMap.Capabilities.Builtin]

  @doc "The configured providers."
  @spec providers() :: [module()]
  def providers do
    # An explicit nil in the configuration means "unset", not "no providers":
    # a registry with no providers would silently empty every surface.
    Application.get_env(:crisis_map, :capability_providers) || @default_providers
  end

  @doc "Every declared capability, in provider and declaration order."
  @spec all() :: [Capability.t()]
  def all do
    Enum.flat_map(providers(), & &1.capabilities())
  end

  @doc """
  Capabilities in the order their HTTP routes must be defined.

  Routes are generated, so their order has to be derived rather than
  remembered: a path with no dynamic segment is defined before one that has
  them, otherwise `/events/:id` would swallow `/events/near`.
  """
  @spec routes() :: [Capability.t()]
  def routes do
    Enum.sort_by(all(), fn %Capability{http: %{path: path}} ->
      dynamic = path |> String.split("/") |> Enum.count(&String.starts_with?(&1, ":"))
      {dynamic, -String.length(path)}
    end)
  end

  @doc "One capability by name, or nil."
  @spec get(String.t()) :: Capability.t() | nil
  def get(name), do: Enum.find(all(), &(&1.name == name))

  @doc "Every declared capability name."
  @spec names() :: [String.t()]
  def names, do: Enum.map(all(), & &1.name)

  @doc """
  Runs a capability by name with raw (uncast) parameters.

  This is the single entry point every surface uses. Parameter casting,
  validation and error shapes are therefore identical whether the call arrived
  over HTTP, over MCP or from the command line.
  """
  @spec dispatch(String.t(), map()) :: {:ok, term()} | {:error, term()}
  def dispatch(name, raw_params \\ %{}) do
    case get(name) do
      nil ->
        {:error, {:not_found, "no capability named #{name}"}}

      capability ->
        with {:ok, params} <- Capability.cast_params(capability, raw_params) do
          capability.handler.(params)
        else
          {:error, message} when is_binary(message) -> {:error, {:bad_request, message}}
          other -> other
        end
    end
  end

  @doc "The self-description of one capability, as `system.capabilities` returns it."
  @spec describe(Capability.t()) :: map()
  def describe(%Capability{} = capability) do
    %{
      name: capability.name,
      summary: capability.summary,
      description: String.trim(capability.description),
      tags: capability.tags,
      mutating: capability.mutating,
      returns: capability.returns,
      http: Capability.http(capability),
      cli: Capability.cli(capability),
      mcp_tool: Capability.tool_name(capability),
      params: Enum.map(capability.params, &describe_param/1),
      examples: Enum.map(capability.examples, &%{description: &1.description, params: &1.params})
    }
  end

  defp describe_param(param) do
    %{
      name: to_string(param.name),
      type: to_string(param.type),
      required: Map.get(param, :required, false),
      description: param.description,
      default: Map.get(param, :default),
      example: Map.get(param, :example)
    }
  end
end
