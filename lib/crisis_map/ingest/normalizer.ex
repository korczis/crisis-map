defmodule CrisisMap.Ingest.Normalizer do
  @moduledoc """
  Turns one raw source record into attributes the domain accepts.

  Normalisation is deliberately total and lossless with respect to the source:
  it trims, parses and maps values, and it never drops the original location
  text. A record it cannot make sense of is returned as an error and reported
  by the importer instead of being silently skipped.
  """

  alias CrisisMap.Catalog

  @type raw :: map()
  @type reason :: {:missing, atom()} | {:invalid, atom(), term()}

  @doc """
  Normalises one record.

  Accepts string- or atom-keyed maps, so a JSON file and an Elixir fixture
  take the same path.
  """
  @spec normalize(raw()) :: {:ok, map()} | {:error, reason()}
  def normalize(raw) when is_map(raw) do
    with {:ok, external_id} <- required_string(raw, "external_id"),
         {:ok, title} <- required_string(raw, "title"),
         {:ok, occurred_at} <- occurred_at(raw) do
      {:ok,
       %{
         external_id: external_id,
         title: title,
         description: trimmed(raw, "description"),
         type: type(raw),
         location_text: trimmed(raw, "location") || trimmed(raw, "location_text"),
         occurred_at: occurred_at
       }}
    end
  end

  @doc """
  Maps a source type onto the catalog.

  An unknown or missing type becomes the catalog's fallback type rather than
  an error: losing an event because a source invented a new label would be
  worse than filing it under "other".
  """
  @spec type(raw()) :: String.t()
  def type(raw) do
    case trimmed(raw, "type") do
      nil ->
        Catalog.fallback_event_type()

      value ->
        canonical = value |> String.downcase() |> String.replace(~r/[\s-]+/u, "_")

        if canonical in Catalog.event_type_ids(),
          do: canonical,
          else: Catalog.fallback_event_type()
    end
  end

  defp occurred_at(raw) do
    case fetch(raw, "occurred_at") do
      nil ->
        {:error, {:missing, :occurred_at}}

      %DateTime{} = dt ->
        {:ok, DateTime.truncate(dt, :second)}

      value when is_binary(value) ->
        case DateTime.from_iso8601(String.trim(value)) do
          {:ok, dt, _offset} -> {:ok, DateTime.truncate(dt, :second)}
          {:error, _} -> {:error, {:invalid, :occurred_at, value}}
        end

      value ->
        {:error, {:invalid, :occurred_at, value}}
    end
  end

  defp required_string(raw, key) do
    case trimmed(raw, key) do
      nil -> {:error, {:missing, String.to_atom(key)}}
      value -> {:ok, value}
    end
  end

  # An empty or whitespace-only string is not a value; it is a missing value
  # written down. Collapsing the two here keeps every downstream check simple.
  defp trimmed(raw, key) do
    case fetch(raw, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  defp fetch(raw, key) do
    Map.get(raw, key) || Map.get(raw, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(raw, key)
  end
end
