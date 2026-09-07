defmodule Mix.Tasks.CrisisMap.Capabilities do
  @shortdoc "Lists every capability with its route, CLI form and MCP tool name"

  @moduledoc """
  Prints the capability registry as a table.

      mix crisis_map.capabilities

  Nothing in this task knows what the capabilities are; it renders whatever
  `CrisisMap.Capabilities.all/0` declares.
  """
  use Mix.Task

  alias CrisisMap.Capabilities
  alias CrisisMap.Capability

  @requirements ["app.config"]

  @impl Mix.Task
  def run(_argv) do
    Mix.shell().info("#{length(Capabilities.all())} capabilities\n")

    for capability <- Capabilities.all() do
      Mix.shell().info("  #{capability.name}  —  #{capability.summary}")
      Mix.shell().info("      http: #{Capability.http(capability)}")
      Mix.shell().info("      cli:  #{Capability.cli(capability)}")
      Mix.shell().info("      mcp:  #{Capability.tool_name(capability)}")
    end
  end
end
