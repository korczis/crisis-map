defmodule CrisisMap.Geocoding do
  @moduledoc """
  The boundary between the domain and whatever resolves place names.

  The domain calls this module; this module calls the adapter configured under
  `config :crisis_map, :geocoder`. In development and production that is
  `CrisisMap.Geocoding.Nominatim`; tests substitute a fake, which is the only
  way to exercise "the geocoder is down" deterministically.

  Every adapter returns the same three shapes, and the caller must handle all
  three:

    * `{:ok, %Result{}}` — a position was found;
    * `{:error, :not_found}` — the geocoder ran and knows nothing;
    * `{:error, reason}` — the geocoder failed. Retryable, never fatal.
  """

  alias CrisisMap.Geocoding.Result

  @callback geocode(String.t()) :: {:ok, Result.t()} | {:error, :not_found} | {:error, term()}
  @callback status() :: {:ok, map()} | {:error, term()}

  @doc "Resolves a place name through the configured adapter."
  @spec geocode(String.t() | nil) :: {:ok, Result.t()} | {:error, :not_found} | {:error, term()}
  def geocode(nil), do: {:error, :not_found}
  def geocode(""), do: {:error, :not_found}
  def geocode(text) when is_binary(text), do: adapter().geocode(text)

  @doc "Health of the configured geocoder, for the status capability."
  @spec status() :: {:ok, map()} | {:error, term()}
  def status, do: adapter().status()

  @doc "The adapter module currently in use."
  @spec adapter() :: module()
  def adapter do
    Application.get_env(:crisis_map, :geocoder, CrisisMap.Geocoding.Nominatim)
  end
end
