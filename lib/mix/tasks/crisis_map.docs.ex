defmodule Mix.Tasks.CrisisMap.Docs do
  @shortdoc "Generates the reference documentation from the registry"

  @moduledoc """
  Writes every generated document under `docs/`.

      mix crisis_map.docs           # write
      mix crisis_map.docs --check   # fail if what is committed is stale

  The `--check` form is a CI gate: it is how a capability that was changed
  without regenerating its documentation becomes a build failure rather than a
  document that quietly stops being true.
  """
  use Mix.Task

  alias CrisisMap.Docs

  @requirements ["app.config"]

  @impl Mix.Task
  def run(argv) do
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: [check: :boolean])

    if opts[:check], do: check(), else: write()
  end

  defp write do
    for {path, content} <- Docs.files() do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
      Mix.shell().info("wrote #{path}")
    end
  end

  defp check do
    stale =
      Docs.files()
      |> Enum.reject(fn {path, content} -> File.exists?(path) and File.read!(path) == content end)
      |> Enum.map(&elem(&1, 0))

    if stale == [] do
      Mix.shell().info("documentation is in sync with the registry")
    else
      Mix.shell().error("stale generated documentation: #{Enum.join(stale, ", ")}")
      Mix.shell().error("run: mix crisis_map.docs")
      exit({:shutdown, 1})
    end
  end
end
