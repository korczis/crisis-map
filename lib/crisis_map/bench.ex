defmodule CrisisMap.Bench do
  @moduledoc """
  The benchmark inventory, derived rather than curated.

  Every capability example is a benchmark case. That is deliberate: a
  benchmark list written by hand goes stale the moment a capability is added,
  whereas this one cannot — the doctrine test asserts that every capability
  appears in the inventory, and the inventory is generated from the same
  examples that the documentation prints and the conformance suite executes.

  Mutating capabilities are measured once rather than repeatedly; the point of
  measuring them is to notice an import that has become pathologically slow,
  not to run it fifty times.
  """

  alias CrisisMap.Capabilities
  alias CrisisMap.Capability

  @default_iterations 20

  @type case_spec :: %{capability: String.t(), description: String.t(), params: map(), iterations: pos_integer()}

  @doc "Every benchmark case."
  @spec inventory(keyword()) :: [case_spec()]
  def inventory(opts \\ []) do
    iterations = Keyword.get(opts, :iterations, @default_iterations)

    for %Capability{} = capability <- Capabilities.all(),
        example <- capability.examples do
      %{
        capability: capability.name,
        description: example.description,
        params: example.params,
        iterations: if(capability.mutating, do: 1, else: iterations)
      }
    end
  end

  @doc """
  Runs the inventory and returns one measurement per case.

  Measurements are wall-clock microseconds around `Capabilities.dispatch/2`,
  which is the same entry point every surface uses, so what is measured is
  what the API and the cockpit actually pay.
  """
  @spec run(keyword()) :: %{generated_at: DateTime.t(), cases: [map()]}
  def run(opts \\ []) do
    cases = Enum.map(inventory(opts), &measure/1)

    %{generated_at: DateTime.utc_now(:second), cases: cases}
  end

  defp measure(spec) do
    samples =
      for _ <- 1..spec.iterations do
        {microseconds, outcome} =
          :timer.tc(fn -> Capabilities.dispatch(spec.capability, spec.params) end)

        {microseconds, outcome}
      end

    durations = Enum.map(samples, &elem(&1, 0))
    failures = Enum.count(samples, fn {_us, outcome} -> not match?({:ok, _}, outcome) end)

    %{
      capability: spec.capability,
      description: spec.description,
      iterations: spec.iterations,
      failures: failures,
      min_ms: round_ms(Enum.min(durations)),
      median_ms: round_ms(median(durations)),
      max_ms: round_ms(Enum.max(durations))
    }
  end

  defp median(values) do
    sorted = Enum.sort(values)
    middle = div(length(sorted), 2)

    case rem(length(sorted), 2) do
      1 -> Enum.at(sorted, middle)
      0 -> (Enum.at(sorted, middle - 1) + Enum.at(sorted, middle)) / 2
    end
  end

  defp round_ms(microseconds), do: Float.round(microseconds / 1000, 3)
end
