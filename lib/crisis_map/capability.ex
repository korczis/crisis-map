defmodule CrisisMap.Capability do
  @moduledoc """
  One operation of this system, declared once.

  A capability is the unit that the doctrine applies to: it carries its own
  documentation, parameter schema, examples and handler, and every surface —
  the CLI, the JSON API, the OpenAPI document, the MCP tool list, the cockpit
  and the generated documentation — is a projection of this declaration. None
  of those surfaces may define an operation of its own, because a second
  definition of the same thing is a second thing that can drift.
  """

  @enforce_keys [:name, :summary, :description, :handler, :http, :returns]
  defstruct [
    :name,
    :summary,
    :description,
    :handler,
    :http,
    :returns,
    params: [],
    examples: [],
    tags: [],
    mutating: false
  ]

  @type param :: %{
          required(:name) => atom(),
          required(:type) => :string | :integer | :float | :boolean,
          required(:description) => String.t(),
          optional(:required) => boolean(),
          optional(:enum) => [String.t()],
          optional(:default) => term(),
          optional(:example) => term()
        }

  @type t :: %__MODULE__{
          name: String.t(),
          summary: String.t(),
          description: String.t(),
          handler: (map() -> {:ok, term()} | {:error, term()}),
          http: %{method: :get | :post, path: String.t()},
          returns: String.t(),
          params: [param()],
          examples: [map()],
          tags: [String.t()],
          mutating: boolean()
        }

  @doc "The MCP tool name for a capability (`events.list` -> `events_list`)."
  @spec tool_name(t()) :: String.t()
  def tool_name(%__MODULE__{name: name}), do: String.replace(name, ".", "_")

  @doc "The CLI invocation for a capability, as documentation shows it."
  @spec cli(t()) :: String.t()
  def cli(%__MODULE__{name: name, params: params}) do
    args =
      params
      |> Enum.filter(&Map.get(&1, :required, false))
      |> Enum.map_join(" ", &"--#{dashed(&1.name)} <#{&1.type}>")

    String.trim("mix crisis_map.run #{name} #{args}")
  end

  @doc "The HTTP line for a capability, as documentation shows it."
  @spec http(t()) :: String.t()
  def http(%__MODULE__{http: %{method: method, path: path}}) do
    "#{method |> Atom.to_string() |> String.upcase()} #{path}"
  end

  @doc "A parameter name as it appears on the command line."
  @spec dashed(atom() | String.t()) :: String.t()
  def dashed(name), do: name |> to_string() |> String.replace("_", "-")

  @doc """
  Casts and validates raw parameters (all strings, as they arrive from HTTP or
  the command line) against the capability's declared schema.

  Validation lives here rather than in each handler, so every surface rejects
  the same input for the same reason.
  """
  @spec cast_params(t(), map()) :: {:ok, map()} | {:error, String.t()}
  def cast_params(%__MODULE__{params: schema}, raw) when is_map(raw) do
    raw = Map.new(raw, fn {key, value} -> {to_string(key), value} end)

    Enum.reduce_while(schema, {:ok, %{}}, fn param, {:ok, acc} ->
      case cast_param(param, Map.get(raw, to_string(param.name))) do
        {:ok, :absent} -> {:cont, {:ok, acc}}
        {:ok, value} -> {:cont, {:ok, Map.put(acc, param.name, value)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp cast_param(param, nil) do
    cond do
      Map.has_key?(param, :default) -> {:ok, param.default}
      Map.get(param, :required, false) -> {:error, "missing required parameter #{param.name}"}
      true -> {:ok, :absent}
    end
  end

  defp cast_param(param, "") do
    if Map.get(param, :required, false),
      do: {:error, "missing required parameter #{param.name}"},
      else: {:ok, :absent}
  end

  defp cast_param(param, value) do
    with {:ok, cast} <- cast_type(param.type, value) do
      validate_enum(param, cast)
    end
  end

  defp cast_type(:string, value) when is_binary(value), do: {:ok, value}
  defp cast_type(:string, value), do: {:ok, to_string(value)}

  defp cast_type(:integer, value) when is_integer(value), do: {:ok, value}

  defp cast_type(:integer, value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _ -> {:error, "#{inspect(value)} is not an integer"}
    end
  end

  defp cast_type(:float, value) when is_float(value), do: {:ok, value}
  defp cast_type(:float, value) when is_integer(value), do: {:ok, value * 1.0}

  defp cast_type(:float, value) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      _ -> {:error, "#{inspect(value)} is not a number"}
    end
  end

  defp cast_type(:boolean, value) when is_boolean(value), do: {:ok, value}
  defp cast_type(:boolean, value) when value in ["true", "1", "yes"], do: {:ok, true}
  defp cast_type(:boolean, value) when value in ["false", "0", "no"], do: {:ok, false}
  defp cast_type(:boolean, value), do: {:error, "#{inspect(value)} is not a boolean"}
  defp cast_type(type, value), do: {:error, "#{inspect(value)} is not a #{type}"}

  defp validate_enum(param, value) do
    case Map.get(param, :enum) do
      nil ->
        {:ok, value}

      allowed ->
        if to_string(value) in allowed,
          do: {:ok, value},
          else: {:error, "#{inspect(value)} is not one of: #{Enum.join(allowed, ", ")}"}
    end
  end

  @doc "The JSON Schema of a capability's parameters, for OpenAPI and MCP."
  @spec json_schema(t()) :: map()
  def json_schema(%__MODULE__{params: params}) do
    properties =
      Map.new(params, fn param ->
        {to_string(param.name),
         %{
           "type" => json_type(param.type),
           "description" => param.description
         }
         |> maybe_put("enum", Map.get(param, :enum))
         |> maybe_put("default", Map.get(param, :default))
         |> maybe_put("example", Map.get(param, :example))}
      end)

    required =
      params |> Enum.filter(&Map.get(&1, :required, false)) |> Enum.map(&to_string(&1.name))

    %{"type" => "object", "properties" => properties, "required" => required}
  end

  defp json_type(:string), do: "string"
  defp json_type(:integer), do: "integer"
  defp json_type(:float), do: "number"
  defp json_type(:boolean), do: "boolean"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
