defmodule Mix.Tasks.CrisisMap.Import do
  @shortdoc "Imports the events dataset (idempotent)"

  @moduledoc """
  Imports a dataset of reported events.

      mix crisis_map.import
      mix crisis_map.import --path priv/data/events.json
      mix crisis_map.import --regeocode

  This is a thin, friendly alias for the `ingest.import` capability — the same
  code path the API, the MCP tool and the cockpit button use. It exists
  because an import is what an operator reaches for first, and it prints a
  readable report rather than JSON.
  """
  use Mix.Task

  alias CrisisMap.Capabilities

  @requirements ["app.start"]

  @impl Mix.Task
  def run(argv) do
    {opts, _rest, _invalid} =
      OptionParser.parse(argv, strict: [path: :string, regeocode: :boolean])

    case Capabilities.dispatch("ingest.import", Map.new(opts)) do
      {:ok, report} ->
        print(report)

      {:error, reason} ->
        Mix.shell().error("import failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp print(report) do
    Mix.shell().info("""
    import finished

      records read        #{report.total}
      inserted            #{report.inserted}
      updated             #{report.updated}
      invalid             #{report.invalid}

      geocoded            #{report.geocoded}
      position reused     #{report.reused}
      location not found  #{report.not_found}
      geocoder errors     #{report.geocoder_errors}
      nothing to geocode  #{report.skipped}
    """)

    case report.errors do
      [] ->
        :ok

      errors ->
        Mix.shell().info("  #{length(errors)} record(s) reported a problem:")

        for %{subject: subject, reason: reason} <- errors do
          Mix.shell().info("    #{subject}: #{reason}")
        end
    end
  end
end
