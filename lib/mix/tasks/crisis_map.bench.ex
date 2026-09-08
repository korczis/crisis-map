defmodule Mix.Tasks.CrisisMap.Bench do
  @shortdoc "Measures every capability through its declared examples"

  @moduledoc """
  Runs the benchmark inventory and prints a table.

      mix crisis_map.bench
      mix crisis_map.bench --iterations 100
      mix crisis_map.bench --json bench/results.json

  The inventory is not written anywhere: it is every example of every
  capability, so a new capability is benchmarked the moment it is declared.
  """
  use Mix.Task

  alias CrisisMap.Bench

  @requirements ["app.start"]

  @impl Mix.Task
  def run(argv) do
    {opts, _rest, _invalid} =
      OptionParser.parse(argv, strict: [iterations: :integer, json: :string])

    results = Bench.run(Keyword.take(opts, [:iterations]))

    Mix.shell().info(
      String.pad_trailing("capability", 30) <>
        String.pad_leading("runs", 6) <>
        String.pad_leading("min ms", 10) <>
        String.pad_leading("median", 10) <>
        String.pad_leading("max ms", 10) <> String.pad_leading("fail", 6)
    )

    for result <- results.cases do
      Mix.shell().info(
        String.pad_trailing(result.capability, 30) <>
          String.pad_leading(to_string(result.iterations), 6) <>
          String.pad_leading(to_string(result.min_ms), 10) <>
          String.pad_leading(to_string(result.median_ms), 10) <>
          String.pad_leading(to_string(result.max_ms), 10) <>
          String.pad_leading(to_string(result.failures), 6)
      )
    end

    if path = opts[:json] do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, Jason.encode_to_iodata!(results, pretty: true))
      Mix.shell().info("\nwrote #{path}")
    end
  end
end
