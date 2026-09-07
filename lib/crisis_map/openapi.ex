defmodule CrisisMap.OpenAPI do
  @moduledoc """
  The OpenAPI document, inferred from the capability registry.

  Nothing here is written twice: paths, methods, parameters, descriptions and
  examples are read from `CrisisMap.Capabilities`, so the specification cannot
  describe an endpoint that does not exist, and an endpoint cannot exist
  without appearing in the specification. There is no hand-maintained YAML in
  this repository, and the doctrine tests fail if anyone adds one.
  """

  alias CrisisMap.Capabilities
  alias CrisisMap.Capability

  @spec spec() :: map()
  def spec do
    %{
      "openapi" => "3.1.0",
      "info" => %{
        "title" => "Crisis Map",
        "version" => version(),
        "description" => """
        Incident reports, normalised, geocoded through a local Nominatim and
        stored with PostGIS geography. Every operation below is a projection of
        the same capability registry that backs the CLI, the MCP server and the
        cockpit.
        """
      },
      "tags" => tags(),
      "paths" => paths(),
      "components" => %{"schemas" => %{}}
    }
  end

  defp version do
    to_string(Application.spec(:crisis_map, :vsn) || "0.0.0")
  end

  defp tags do
    Capabilities.all()
    |> Enum.flat_map(& &1.tags)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&%{"name" => &1})
  end

  defp paths do
    Capabilities.all()
    |> Enum.group_by(&openapi_path(&1.http.path))
    |> Map.new(fn {path, capabilities} ->
      {path, Map.new(capabilities, &{Atom.to_string(&1.http.method), operation(&1)})}
    end)
  end

  # Phoenix writes `:id`, OpenAPI writes `{id}`.
  defp openapi_path(path) do
    Regex.replace(~r/:([a-z_]+)/, path, "{\\1}")
  end

  defp operation(%Capability{} = capability) do
    %{
      "operationId" => capability.name,
      "summary" => capability.summary,
      "description" => String.trim(capability.description),
      "tags" => capability.tags,
      "parameters" => Enum.map(capability.params, &parameter(capability, &1)),
      "responses" => %{
        "200" => %{
          "description" => capability.returns,
          "content" => %{
            "application/json" => %{
              "schema" => %{
                "type" => "object",
                "properties" => %{
                  "capability" => %{"type" => "string"},
                  "data" => %{"description" => capability.returns}
                }
              },
              "examples" => examples(capability)
            }
          }
        },
        "400" => %{"description" => "A parameter failed the capability's own validation."},
        "404" => %{"description" => "No such capability or no such record."}
      }
    }
  end

  defp parameter(%Capability{http: %{path: path}}, param) do
    name = to_string(param.name)
    in_path? = String.contains?(path, ":" <> name)

    %{
      "name" => name,
      "in" => if(in_path?, do: "path", else: "query"),
      "required" => in_path? or Map.get(param, :required, false),
      "description" => param.description,
      "schema" =>
        %{"type" => json_type(param.type)}
        |> maybe_put("enum", Map.get(param, :enum))
        |> maybe_put("default", Map.get(param, :default)),
      "example" => Map.get(param, :example)
    }
  end

  # The examples in the specification are the examples the conformance suite
  # executes, so a stale example is a failing test rather than a lie in the docs.
  defp examples(%Capability{examples: []}), do: %{}

  defp examples(%Capability{examples: examples}) do
    examples
    |> Enum.with_index(1)
    |> Map.new(fn {example, index} ->
      {"example#{index}",
       %{"summary" => example.description, "value" => %{"params" => stringify(example.params)}}}
    end)
  end

  defp stringify(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end

  defp json_type(:string), do: "string"
  defp json_type(:integer), do: "integer"
  defp json_type(:float), do: "number"
  defp json_type(:boolean), do: "boolean"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
