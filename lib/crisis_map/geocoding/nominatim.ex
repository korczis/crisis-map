defmodule CrisisMap.Geocoding.Nominatim do
  @moduledoc """
  Forward geocoding against a local Nominatim instance.

  This module is infrastructure: it speaks HTTP and knows Nominatim's response
  shape, and it is the only place in the system that does. It never raises —
  a timeout, a connection refusal or a 5xx all come back as `{:error, reason}`
  so that one unreachable geocoder cannot take an import down with it.

  Ambiguity is handled explicitly. Nominatim answers with a list ranked by its
  own `importance` score; we ask for several candidates, take the first, and
  carry the number of candidates and the score into the result. We never merge
  candidates and never average coordinates.
  """

  @behaviour CrisisMap.Geocoding

  require Logger

  alias CrisisMap.Geocoding.Result

  @candidate_limit 5

  @impl true
  def geocode(text) when is_binary(text) do
    params = [
      q: text,
      format: "jsonv2",
      limit: @candidate_limit,
      addressdetails: 0
    ]

    params = if country_codes(), do: Keyword.put(params, :countrycodes, country_codes()), else: params

    case request("/search", params) do
      {:ok, %Req.Response{status: 200, body: results}} when is_list(results) ->
        parse_candidates(results)

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, {:transport, reason}}
    end
  end

  @impl true
  def status do
    case request("/status.php", format: "json") do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, normalize_status(body)}
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, {:transport, reason}}
    end
  end

  defp parse_candidates([]), do: {:error, :not_found}

  defp parse_candidates([best | _] = results) do
    with {:ok, lat} <- parse_float(Map.get(best, "lat")),
         {:ok, lon} <- parse_float(Map.get(best, "lon")) do
      {:ok,
       %Result{
         lat: lat,
         lon: lon,
         display_name: Map.get(best, "display_name"),
         confidence: parse_confidence(Map.get(best, "importance")),
         candidates: length(results)
       }}
    else
      :error -> {:error, {:malformed_response, best}}
    end
  end

  defp request(path, params) do
    Req.get(base_url() <> path,
      params: params,
      receive_timeout: receive_timeout(),
      connect_options: [timeout: connect_timeout()],
      retry: false,
      headers: [{"user-agent", user_agent()}]
    )
  rescue
    # Req raises on some transport-level failures; the caller must never see
    # an exception, only a reason.
    exception -> {:error, {:exception, Exception.message(exception)}}
  end

  defp parse_float(value) when is_float(value), do: {:ok, value}
  defp parse_float(value) when is_integer(value), do: {:ok, value * 1.0}

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _rest} -> {:ok, float}
      :error -> :error
    end
  end

  defp parse_float(_), do: :error

  defp parse_confidence(value) do
    case parse_float(value) do
      {:ok, float} -> float
      :error -> nil
    end
  end

  defp normalize_status(body) when is_map(body) do
    %{
      adapter: "nominatim",
      base_url: base_url(),
      status: Map.get(body, "status"),
      message: Map.get(body, "message"),
      data_updated: Map.get(body, "data_updated")
    }
  end

  defp normalize_status(_), do: %{adapter: "nominatim", base_url: base_url()}

  defp config, do: Application.get_env(:crisis_map, __MODULE__, [])
  defp base_url, do: Keyword.get(config(), :base_url, "http://localhost:8080")
  defp country_codes, do: Keyword.get(config(), :country_codes)
  defp receive_timeout, do: Keyword.get(config(), :receive_timeout, 5_000)
  defp connect_timeout, do: Keyword.get(config(), :connect_timeout, 2_000)
  defp user_agent, do: Keyword.get(config(), :user_agent, "crisis_map/0.1 (local academy exercise)")
end
