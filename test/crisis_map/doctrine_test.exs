defmodule CrisisMap.DoctrineTest do
  @moduledoc """
  The rules that keep the registry and its projections from drifting apart.

  These are not tests of behaviour; they are the enforcement of the contract
  this repository is built on. Every one of them fails loudly when a
  capability is declared without documentation, without an example, without a
  route, without a test or without regenerating the documentation — which is
  the only reason the claim "one source of truth" stays true after the day it
  was made.
  """
  use CrisisMapWeb.ConnCase, async: true

  alias CrisisMap.Bench
  alias CrisisMap.Capabilities
  alias CrisisMap.Capability
  alias CrisisMap.Catalog
  alias CrisisMap.Docs
  alias CrisisMap.OpenAPI

  @test_sources Path.wildcard("test/**/*.exs")

  describe "every capability is documented" do
    test "with a summary, a description and a statement of what it returns" do
      for capability <- Capabilities.all() do
        assert String.length(capability.summary) > 5,
               "#{capability.name}: summary is too thin to be documentation"

        assert String.length(String.trim(capability.description)) > 120,
               "#{capability.name}: description does not explain the operation"

        assert String.length(capability.returns) > 10,
               "#{capability.name}: does not say what it returns"
      end
    end

    test "with every parameter described" do
      for capability <- Capabilities.all(), param <- capability.params do
        assert String.length(param.description) > 10,
               "#{capability.name}/#{param.name}: parameter is undescribed"

        assert param.type in [:string, :integer, :float, :boolean],
               "#{capability.name}/#{param.name}: undeclared parameter type"
      end
    end

    test "with at least one runnable example" do
      for capability <- Capabilities.all() do
        assert capability.examples != [], "#{capability.name}: has no example"

        for example <- capability.examples do
          assert {:ok, _params} = Capability.cast_params(capability, example.params),
                 "#{capability.name}: example #{inspect(example.description)} does not satisfy its own schema"
        end
      end
    end

    test "and appears in the generated reference" do
      reference = Docs.capabilities_markdown()

      for capability <- Capabilities.all() do
        assert reference =~ capability.name, "#{capability.name}: missing from docs/CAPABILITIES.md"
      end
    end
  end

  describe "the generated documentation is in sync" do
    test "every generated file matches what the registry would produce now" do
      for {path, expected} <- Docs.files() do
        assert File.exists?(path), "#{path} has never been generated — run: mix crisis_map.docs"

        assert File.read!(path) == expected,
               "#{path} is stale — run: mix crisis_map.docs"
      end
    end

    test "no hand-written API specification is kept alongside the inferred one" do
      hand_written =
        Path.wildcard("{docs,priv,assets}/**/*.{yaml,yml}")
        |> Enum.filter(&(String.contains?(Path.basename(&1), "openapi") or String.contains?(Path.basename(&1), "swagger")))

      assert hand_written == [],
             "a second definition of the API exists and will drift: #{inspect(hand_written)}"
    end
  end

  describe "every capability reaches every surface" do
    test "an HTTP route exists with the declared method and path" do
      routes = MapSet.new(CrisisMapWeb.Router.__routes__(), &{&1.verb, &1.path})

      for capability <- Capabilities.all() do
        assert MapSet.member?(routes, {capability.http.method, capability.http.path}),
               "#{capability.name}: no route for #{Capability.http(capability)}"
      end
    end

    test "the OpenAPI document describes it" do
      paths = OpenAPI.spec()["paths"]

      operation_ids =
        for {_path, operations} <- paths, {_method, operation} <- operations, do: operation["operationId"]

      for capability <- Capabilities.all() do
        assert capability.name in operation_ids,
               "#{capability.name}: missing from the OpenAPI document"
      end
    end

    test "the MCP tool list exposes it with a schema" do
      {:ok, %{tools: tools}} = mcp("tools/list")
      names = Enum.map(tools, & &1.name)

      for capability <- Capabilities.all() do
        tool_name = Capability.tool_name(capability)
        assert tool_name in names, "#{capability.name}: not exposed as an MCP tool"

        tool = Enum.find(tools, &(&1.name == tool_name))
        assert %{"type" => "object", "properties" => _, "required" => _} = tool.inputSchema
      end
    end

    test "the command line accepts it" do
      for capability <- Capabilities.all() do
        assert Capability.cli(capability) =~ "mix crisis_map.run #{capability.name}"
      end
    end

    test "the benchmark inventory measures it" do
      measured = Bench.inventory() |> Enum.map(& &1.capability) |> MapSet.new()

      for capability <- Capabilities.all() do
        assert MapSet.member?(measured, capability.name),
               "#{capability.name}: not covered by any benchmark case"
      end
    end

    test "a test names it" do
      sources = Enum.map(@test_sources, &File.read!/1)

      for capability <- Capabilities.all() do
        assert Enum.any?(sources, &String.contains?(&1, capability.name)),
               "#{capability.name}: no test mentions this capability"
      end
    end
  end

  describe "the catalog is well formed" do
    test "event types are unique, labelled, described and coloured" do
      types = Catalog.event_types()

      assert length(Enum.uniq_by(types, & &1.id)) == length(types)
      assert length(Enum.uniq_by(types, & &1.color)) == length(types), "two types share a map colour"

      for type <- types do
        assert type.id =~ ~r/^[a-z_]+$/
        assert String.length(type.label) > 2
        assert String.length(type.description) > 10, "#{type.id}: undescribed event type"
        assert type.color =~ ~r/^#[0-9a-f]{6}$/
      end
    end

    test "the fallback type is itself a declared type" do
      assert Catalog.fallback_event_type() in Catalog.event_type_ids()
    end

    test "every geocoding status says whether coordinates are known" do
      for status <- Catalog.geocoding_statuses() do
        assert is_boolean(status.coordinates_known)
        assert String.length(status.description) > 10, "#{status.id}: undescribed status"
      end
    end

    test "exactly one status means the coordinates are known" do
      known = Enum.filter(Catalog.geocoding_statuses(), & &1.coordinates_known)

      assert length(known) == 1,
             "more than one status claims coordinates exist; the schema invariant assumes one"
    end
  end

  describe "the code is documented" do
    test "every module of the application carries a moduledoc" do
      undocumented =
        Application.spec(:crisis_map, :modules)
        |> Enum.filter(&match?({:docs_v1, _, _, _, :none, _, _}, Code.fetch_docs(&1)))

      assert undocumented == [], "modules without a moduledoc: #{inspect(undocumented)}"
    end
  end

  defp mcp(method, params \\ %{}) do
    result =
      build_conn()
      |> post("/mcp", %{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params})
      |> json_response(200)
      |> Map.fetch!("result")
      |> atomize()

    {:ok, result}
  end

  defp atomize(%{} = map) do
    Map.new(map, fn
      {"tools", tools} -> {:tools, Enum.map(tools, &atomize/1)}
      {"name", value} -> {:name, value}
      {"inputSchema", value} -> {:inputSchema, value}
      {key, value} -> {String.to_atom(key), value}
    end)
  end
end
