defmodule CrisisMap.CapabilityProvidersTest do
  @moduledoc """
  The registry aggregates providers; it does not own a list.

  These tests change application configuration, which is global, so they are
  synchronous — and they are what proves an operation can be contributed from
  outside this application and still reach every surface built at run time.
  """
  use CrisisMap.DataCase, async: false

  alias CrisisMap.Capabilities

  describe "providers" do
    setup do
      previous = Application.get_env(:crisis_map, :capability_providers)

      Application.put_env(:crisis_map, :capability_providers, [
        CrisisMap.Capabilities.Builtin,
        CrisisMap.TestExtension
      ])

      on_exit(fn -> Application.put_env(:crisis_map, :capability_providers, previous) end)
      :ok
    end

    test "a capability declared outside the application is dispatchable like any other" do
      assert "extension.echo" in Capabilities.names()
      assert {:ok, %{echo: "hi"}} = Capabilities.dispatch("extension.echo", %{"message" => "hi"})
    end

    test "and it reaches the surfaces that are built at run time" do
      assert Enum.any?(CrisisMap.Bench.inventory(), &(&1.capability == "extension.echo"))
      assert CrisisMap.Docs.capabilities_markdown() =~ "extension.echo"

      operation_ids =
        for {_path, operations} <- CrisisMap.OpenAPI.spec()["paths"],
            {_method, operation} <- operations,
            do: operation["operationId"]

      assert "extension.echo" in operation_ids
    end
  end
end
