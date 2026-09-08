defmodule Mix.Tasks.CrisisMap.Site do
  @shortdoc "Generates the static site published to GitHub Pages"

  @moduledoc """
  Renders the site into a directory.

      mix crisis_map.site              # into site/
      mix crisis_map.site --out _site  # anywhere else

  The site is generated from the capability registry and the catalog, which is
  why it is not committed: CI builds it from the code it is publishing.
  """
  use Mix.Task

  alias CrisisMap.Site

  @requirements ["app.config"]

  @impl Mix.Task
  def run(argv) do
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: [out: :string])
    out = Keyword.get(opts, :out, "site")

    File.mkdir_p!(out)

    for {path, content} <- Site.files() do
      target = Path.join(out, path)
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, content)
      Mix.shell().info("wrote #{target}")
    end
  end
end
