defmodule CrisisMap.TestExtension do
  @moduledoc """
  A capability provider defined outside the registry, used to prove that the
  registry is extensible from outside rather than a list one application owns.
  """

  @behaviour CrisisMap.Capabilities.Provider

  alias CrisisMap.Capability

  @impl true
  def capabilities do
    [
      %Capability{
        name: "extension.echo",
        summary: "Echo a message",
        description:
          "An operation contributed by a provider outside the application, to prove the registry aggregates rather than owns.",
        tags: ["extension"],
        http: %{method: :get, path: "/api/v1/extension/echo"},
        returns: "The message that was sent.",
        params: [
          %{
            name: :message,
            type: :string,
            required: true,
            description: "Anything at all.",
            example: "hi"
          }
        ],
        examples: [%{description: "Echo", params: %{message: "hi"}}],
        handler: fn %{message: message} -> {:ok, %{echo: message}} end
      }
    ]
  end
end
