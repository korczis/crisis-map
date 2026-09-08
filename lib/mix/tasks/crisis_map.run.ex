defmodule Mix.Tasks.CrisisMap.Run do
  @shortdoc "Runs any capability from the command line"

  @moduledoc """
  The command-line projection of the capability registry.

      mix crisis_map.run <capability> [--param value ...]

  The capability list is not written here: it is read from
  `CrisisMap.Capabilities`, so every capability is runnable from the shell the
  moment it is declared. `mix crisis_map.capabilities` prints what is
  available.

      mix crisis_map.run events.stats
      mix crisis_map.run events.near --lat 50.0755 --lon 14.4378 --radius-km 50
      mix crisis_map.run geocoding.lookup --query Beroun
  """
  use Mix.Task

  alias CrisisMap.Capabilities
  alias CrisisMap.Capability

  @requirements ["app.start"]

  @impl Mix.Task
  def run([]) do
    Mix.shell().error("usage: mix crisis_map.run <capability> [--param value ...]")
    Mix.shell().info("")
    Mix.Tasks.CrisisMap.Capabilities.run([])
    exit({:shutdown, 2})
  end

  def run([name | argv]) do
    case Capabilities.get(name) do
      nil ->
        Mix.shell().error("unknown capability: #{name}")
        Mix.shell().info("known: #{Enum.join(Capabilities.names(), ", ")}")
        exit({:shutdown, 2})

      capability ->
        capability
        |> parse_params(argv)
        |> then(&Capabilities.dispatch(name, &1))
        |> report()
    end
  end

  # Switches are derived from the declared parameters, so the CLI accepts
  # exactly what the API and MCP accept.
  defp parse_params(%Capability{params: params}, argv) do
    switches = Enum.map(params, &{switch_key(&1.name), switch_type(&1.type)})

    {parsed, _rest, invalid} = OptionParser.parse(argv, strict: switches)

    if invalid != [] do
      Mix.shell().error("unknown or malformed options: #{inspect(invalid)}")
      exit({:shutdown, 2})
    end

    Map.new(parsed, fn {key, value} ->
      {key |> Atom.to_string() |> String.replace("-", "_"), value}
    end)
  end

  defp switch_key(name), do: name |> to_string() |> String.replace("_", "-") |> String.to_atom()

  defp switch_type(:integer), do: :integer
  defp switch_type(:float), do: :float
  defp switch_type(:boolean), do: :boolean
  defp switch_type(_), do: :string

  defp report({:ok, value}) do
    Mix.shell().info(Jason.encode_to_iodata!(value, pretty: true) |> IO.iodata_to_binary())
  end

  defp report({:error, {_kind, message}}) do
    Mix.shell().error(to_string(message))
    exit({:shutdown, 1})
  end

  defp report({:error, reason}) do
    Mix.shell().error(inspect(reason))
    exit({:shutdown, 1})
  end
end
