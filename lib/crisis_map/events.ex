defmodule CrisisMap.Events do
  @moduledoc """
  The event domain: everything the rest of the system is allowed to do with
  stored incidents.

  This module owns persistence and querying. It knows about Ecto and PostGIS;
  nothing above it (the LiveView, the JSON API, the CLI, the MCP tools) writes
  a query of its own.
  """

  import Ecto.Query

  alias CrisisMap.Catalog
  alias CrisisMap.Events.Event
  alias CrisisMap.Repo

  @default_order [desc: :occurred_at]

  @doc """
  Lists events, newest first.

  Filters (all optional, all combinable):

    * `:type` — a catalog event type id, or `"all"`/`nil` for every type;
    * `:located` — `true` keeps only events with known coordinates;
    * `:within` — `%{lat: float, lon: float, radius_km: number}`, a PostGIS
      radius search that also returns `distance_m` on every row;
    * `:limit` — maximum number of rows.
  """
  @spec list_events(map() | keyword()) :: [Event.t()]
  def list_events(filters \\ %{}) do
    filters = Map.new(filters)

    Event
    |> filter_by_type(Map.get(filters, :type))
    |> filter_located(Map.get(filters, :located))
    |> filter_within(Map.get(filters, :within))
    |> order_by(^@default_order)
    |> maybe_limit(Map.get(filters, :limit))
    |> Repo.all()
  end

  @doc "One event by primary key, or nil."
  @spec get_event(integer() | String.t()) :: Event.t() | nil
  def get_event(id), do: Repo.get(Event, id)

  @doc "One event by its source identifier, or nil."
  @spec get_event_by_external_id(String.t()) :: Event.t() | nil
  def get_event_by_external_id(external_id), do: Repo.get_by(Event, external_id: external_id)

  @doc "How many events are stored per type, including types with no events."
  @spec count_by_type() :: %{String.t() => non_neg_integer()}
  def count_by_type do
    counted =
      Event
      |> group_by([e], e.type)
      |> select([e], {e.type, count(e.id)})
      |> Repo.all()
      |> Map.new()

    Catalog.event_type_ids()
    |> Map.new(&{&1, Map.get(counted, &1, 0)})
  end

  @doc "How many events are stored per geocoding status."
  @spec count_by_geocoding_status() :: %{String.t() => non_neg_integer()}
  def count_by_geocoding_status do
    counted =
      Event
      |> group_by([e], e.geocoding_status)
      |> select([e], {e.geocoding_status, count(e.id)})
      |> Repo.all()
      |> Map.new()

    Catalog.geocoding_status_ids()
    |> Map.new(&{&1, Map.get(counted, &1, 0)})
  end

  @doc "Total number of stored events."
  @spec count_events() :: non_neg_integer()
  def count_events, do: Repo.aggregate(Event, :count, :id)

  @doc """
  Inserts or updates one event by its source identifier.

  This is the idempotency boundary of the whole ingest path: `external_id` is
  the source's own identity for the incident and carries a unique index, so a
  record that arrives twice updates the same row instead of creating a second
  one. Only *source* fields are written here — a re-import never destroys a
  position we already resolved.
  """
  @spec upsert_from_source(map()) ::
          {:ok, {:inserted | :updated, Event.t()}} | {:error, Ecto.Changeset.t()}
  def upsert_from_source(attrs) do
    case get_event_by_external_id(attrs.external_id) do
      nil ->
        %Event{}
        |> Event.changeset(attrs)
        |> Repo.insert()
        |> case do
          {:ok, event} ->
            {:ok, {:inserted, event}}

          # Lost a race with a concurrent importer: the row exists now, so
          # take the update path instead of failing the record.
          {:error, changeset} ->
            if unique_violation?(changeset) do
              attrs.external_id |> get_event_by_external_id() |> update_source(attrs)
            else
              {:error, changeset}
            end
        end

      existing ->
        update_source(existing, attrs)
    end
  end

  defp unique_violation?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn {field, {_message, opts}} ->
      field == :external_id and Keyword.get(opts, :constraint) == :unique
    end)
  end

  defp update_source(existing, attrs) do
    existing
    |> Event.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, event} -> {:ok, {:updated, event}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Writes the outcome of a geocoding attempt onto an event.

  Every outcome — including "nothing found" and "the geocoder is down" — is
  recorded, so the reason a point is missing is always visible in the row.
  """
  @spec put_geocoding(Event.t(), map()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def put_geocoding(%Event{} = event, attrs) do
    event
    |> Event.changeset(Map.put_new(attrs, :geocoded_at, DateTime.utc_now(:second)))
    |> Repo.update()
  end

  @doc "Deletes every event. Used by the CLI reset and by tests."
  @spec delete_all_events() :: non_neg_integer()
  def delete_all_events do
    {count, _} = Repo.delete_all(Event)
    count
  end

  defp filter_by_type(query, type) when type in [nil, "", "all"], do: query
  defp filter_by_type(query, type), do: where(query, [e], e.type == ^type)

  defp filter_located(query, true), do: where(query, [e], not is_nil(e.geom))
  defp filter_located(query, _), do: query

  defp filter_within(query, nil), do: query

  defp filter_within(query, %{lat: lat, lon: lon} = within) do
    radius_m = (Map.get(within, :radius_km) || 0) * 1000.0
    lat = to_float(lat)
    lon = to_float(lon)

    # The spatial predicate proper. `geom` is a geography column, so ST_DWithin
    # takes metres and measures on the spheroid, and the GiST index on `geom`
    # answers it without scanning the table. ST_Distance returns the same
    # measure, which is what the UI shows and orders by.
    query
    |> where([e], not is_nil(e.geom))
    |> where(
      [e],
      fragment(
        "ST_DWithin(?, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)",
        e.geom,
        ^lon,
        ^lat,
        ^radius_m
      )
    )
    |> select_merge([e], %{
      distance_m:
        fragment(
          "ST_Distance(?, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography)",
          e.geom,
          ^lon,
          ^lat
        )
    })
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit) when is_integer(limit), do: limit(query, ^limit)

  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value * 1.0
  defp to_float(value) when is_binary(value), do: String.to_float(value)
end
