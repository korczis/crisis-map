defmodule CrisisMap.Capabilities.Provider do
  @moduledoc """
  What a capability provider must implement.

  A provider is any module that returns a list of `CrisisMap.Capability`
  structs. The registry reads the providers listed under
  `config :crisis_map, :capability_providers`, so an operation can be added by
  a separate application without touching this one, and it then appears on
  every surface the registry projects onto.

  One caveat, stated here because it is the only place it can be honest: the
  REST routes are generated at compile time, so a provider added to the
  configuration after compilation is reachable from the CLI, the MCP server
  and the cockpit, but its HTTP route only exists once the router is
  recompiled.
  """

  @callback capabilities() :: [CrisisMap.Capability.t()]
end
