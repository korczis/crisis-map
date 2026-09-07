defmodule CrisisMap.Events.Event do
  @moduledoc """
  One reported incident.

  The schema keeps two clearly separated groups of fields:

    * *source* fields (`external_id`, `title`, `description`, `type`,
      `location_text`, `occurred_at`) come from the input record and are only
      normalised, never invented;
    * *derived* fields (`geom` and everything prefixed `geocod*`) are produced
      by this system and always carry the evidence of how they were produced.

  `geom` is `NULL` whenever the position is unknown. There is no sentinel
  coordinate, no 0/0 and no guessed centroid: `geocoding_status` says why the
  position is missing.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias CrisisMap.Catalog

  @type t :: %__MODULE__{}

  @source_fields [:external_id, :title, :description, :type, :location_text, :occurred_at]
  @derived_fields [
    :geom,
    :geocoding_status,
    :geocoded_display_name,
    :geocoding_candidates,
    :geocoding_confidence,
    :geocoded_at
  ]

  schema "events" do
    field :external_id, :string
    field :title, :string
    field :description, :string
    field :type, :string
    field :location_text, :string
    field :occurred_at, :utc_datetime

    field :geom, Geo.PostGIS.Geometry
    field :geocoding_status, :string, default: "pending"
    field :geocoded_display_name, :string
    field :geocoding_candidates, :integer
    field :geocoding_confidence, :float
    field :geocoded_at, :utc_datetime

    # Populated only by queries that ask for it (see Events.list_events/1).
    field :distance_m, :float, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc "The fields that are taken verbatim (after normalisation) from the source."
  @spec source_fields() :: [atom()]
  def source_fields, do: @source_fields

  @doc "The fields this system computes."
  @spec derived_fields() :: [atom()]
  def derived_fields, do: @derived_fields

  @doc """
  Validates a normalised record.

  Anything that reaches this function has already been through
  `CrisisMap.Ingest.Normalizer`; the changeset is the last boundary check, so
  it repeats the invariants rather than trusting the caller.
  """
  def changeset(event, attrs) do
    event
    |> cast(attrs, @source_fields ++ @derived_fields)
    |> validate_required([:external_id, :title, :type, :occurred_at])
    |> validate_inclusion(:type, Catalog.event_type_ids())
    |> validate_inclusion(:geocoding_status, Catalog.geocoding_status_ids())
    |> validate_coordinates_match_status()
    |> unique_constraint(:external_id)
  end

  # The one invariant that ties the derived fields together: a status that
  # claims coordinates are known must come with a point, and a status that
  # claims they are unknown must not carry one.
  defp validate_coordinates_match_status(changeset) do
    status = get_field(changeset, :geocoding_status)
    geom = get_field(changeset, :geom)
    known? = match?(%{coordinates_known: true}, Catalog.geocoding_status(status))

    cond do
      known? and is_nil(geom) ->
        add_error(changeset, :geom, "is required when geocoding_status is #{status}")

      not known? and not is_nil(geom) ->
        add_error(changeset, :geom, "must be empty when geocoding_status is #{status}")

      true ->
        changeset
    end
  end

  @doc "Latitude of the event, or nil when the position is unknown."
  @spec latitude(t()) :: float() | nil
  def latitude(%__MODULE__{geom: %Geo.Point{coordinates: {_lon, lat}}}), do: lat
  def latitude(%__MODULE__{}), do: nil

  @doc "Longitude of the event, or nil when the position is unknown."
  @spec longitude(t()) :: float() | nil
  def longitude(%__MODULE__{geom: %Geo.Point{coordinates: {lon, _lat}}}), do: lon
  def longitude(%__MODULE__{}), do: nil

  @doc "True when the event can be drawn on a map."
  @spec located?(t()) :: boolean()
  def located?(%__MODULE__{geom: %Geo.Point{}}), do: true
  def located?(%__MODULE__{}), do: false
end
