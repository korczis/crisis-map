defmodule CrisisMap.EventsFixtures do
  @moduledoc "Stored events, for tests that start from data rather than from an import."

  alias CrisisMap.Events

  @doc """
  Creates one stored event.

  `:at` places it (`{lat, lon}`); omitting it leaves the position unknown, the
  way a failed geocoding does.
  """
  def event_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)

    {:ok, {_outcome, event}} =
      Events.upsert_from_source(%{
        external_id: Map.get(attrs, :external_id, "event-#{System.unique_integer([:positive])}"),
        title: Map.get(attrs, :title, "Dopravní nehoda"),
        description: Map.get(attrs, :description, "Střet dvou osobních vozidel."),
        type: Map.get(attrs, :type, "traffic_accident"),
        location_text: Map.get(attrs, :location_text, "Beroun"),
        occurred_at: Map.get(attrs, :occurred_at, ~U[2026-08-28 08:15:00Z])
      })

    case Map.get(attrs, :at) do
      {lat, lon} ->
        {:ok, event} =
          Events.put_geocoding(event, %{
            geom: %Geo.Point{coordinates: {lon, lat}, srid: 4326},
            geocoding_status: "ok",
            geocoded_display_name: Map.get(attrs, :location_text, "Beroun"),
            geocoding_candidates: 1,
            geocoding_confidence: 0.7
          })

        event

      nil ->
        {:ok, event} = Events.put_geocoding(event, %{geocoding_status: "not_found", geom: nil})
        event
    end
  end
end
