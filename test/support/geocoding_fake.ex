defmodule CrisisMap.Geocoding.Fake do
  @moduledoc """
  The geocoder used in tests.

  It is an adapter like `CrisisMap.Geocoding.Nominatim`, selected by
  configuration rather than by a flag in the domain, which is what makes
  "the geocoder is down" and "the geocoder found nothing" reproducible
  instead of dependent on somebody's local container.

  The script lives in the calling process, so tests stay async: the ingest
  pipeline runs in the test process and reads the script the test installed.
  """

  @behaviour CrisisMap.Geocoding

  alias CrisisMap.Geocoding.Result

  @key {__MODULE__, :script}

  @doc "Installs a function that answers every lookup."
  @spec script((String.t() -> {:ok, Result.t()} | {:error, term()})) :: :ok
  def script(fun) when is_function(fun, 1) do
    Process.put(@key, fun)
    :ok
  end

  @doc "Answers every lookup with the same result."
  @spec always({:ok, Result.t()} | {:error, term()}) :: :ok
  def always(answer), do: script(fn _query -> answer end)

  @doc "Answers from a map of place name to result; anything else is not found."
  @spec known(%{String.t() => {float(), float()}}) :: :ok
  def known(places) do
    script(fn query ->
      case Map.fetch(places, query) do
        {:ok, {lat, lon}} ->
          {:ok, %Result{lat: lat, lon: lon, display_name: query, confidence: 0.7, candidates: 1}}

        :error ->
          {:error, :not_found}
      end
    end)
  end

  @impl true
  def geocode(query) do
    case Process.get(@key) do
      nil -> {:error, :not_found}
      fun -> fun.(query)
    end
  end

  @impl true
  def status, do: {:ok, %{adapter: "fake", reachable: true}}
end
