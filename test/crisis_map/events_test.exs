defmodule CrisisMap.EventsTest do
  @moduledoc """
  The domain's own guarantees: the invariant between a position and the status
  that explains it, and the PostGIS predicate that makes "within X km" a
  database question rather than an application loop.
  """
  use CrisisMap.DataCase, async: true

  alias CrisisMap.Events
  alias CrisisMap.Events.Event

  # Real coordinates, so the distances below are real distances.
  @praha {50.0755, 14.4378}
  @beroun {49.9639, 14.0722}
  @ostrava {49.8209, 18.2625}

  defp create(attrs) do
    {lat, lon} = Map.get(attrs, :at, @praha)

    base = %{
      external_id: Map.fetch!(attrs, :external_id),
      title: Map.get(attrs, :title, "Událost"),
      type: Map.get(attrs, :type, "fire"),
      location_text: Map.get(attrs, :location_text, "Praha"),
      occurred_at: Map.get(attrs, :occurred_at, ~U[2026-08-28 08:15:00Z])
    }

    {:ok, {_outcome, event}} = Events.upsert_from_source(base)

    if Map.get(attrs, :located, true) do
      {:ok, event} =
        Events.put_geocoding(event, %{
          geom: %Geo.Point{coordinates: {lon, lat}, srid: 4326},
          geocoding_status: "ok"
        })

      event
    else
      {:ok, event} = Events.put_geocoding(event, %{geocoding_status: "not_found", geom: nil})
      event
    end
  end

  describe "the position invariant" do
    test "a status that claims coordinates cannot be stored without a point" do
      changeset =
        Event.changeset(%Event{}, %{
          external_id: "event-1",
          title: "Událost",
          type: "fire",
          occurred_at: ~U[2026-08-28 08:15:00Z],
          geocoding_status: "ok"
        })

      refute changeset.valid?
      assert %{geom: ["is required when geocoding_status is ok"]} = errors_on(changeset)
    end

    test "a status that denies coordinates cannot be stored with a point" do
      changeset =
        Event.changeset(%Event{}, %{
          external_id: "event-1",
          title: "Událost",
          type: "fire",
          occurred_at: ~U[2026-08-28 08:15:00Z],
          geocoding_status: "not_found",
          geom: %Geo.Point{coordinates: {14.4378, 50.0755}, srid: 4326}
        })

      refute changeset.valid?
      assert %{geom: ["must be empty when geocoding_status is not_found"]} = errors_on(changeset)
    end

    test "a type outside the catalog is rejected at the boundary" do
      changeset =
        Event.changeset(%Event{}, %{
          external_id: "event-1",
          title: "Událost",
          type: "meteorite_strike",
          occurred_at: ~U[2026-08-28 08:15:00Z]
        })

      refute changeset.valid?
      assert %{type: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "list_events/1 spatial filter" do
    setup do
      %{
        praha: create(%{external_id: "praha", at: @praha, type: "fire"}),
        beroun: create(%{external_id: "beroun", at: @beroun, type: "traffic_accident"}),
        ostrava: create(%{external_id: "ostrava", at: @ostrava, type: "fire"}),
        nowhere: create(%{external_id: "nowhere", located: false})
      }
    end

    test "keeps what is inside the radius and drops what is outside" do
      within_50 = Events.list_events(%{within: %{lat: 50.0755, lon: 14.4378, radius_km: 50}})
      ids = Enum.map(within_50, & &1.external_id)

      # Beroun is ~30 km from Prague, Ostrava ~280 km.
      assert "praha" in ids
      assert "beroun" in ids
      refute "ostrava" in ids
    end

    test "never returns an event whose position is unknown" do
      ids =
        %{within: %{lat: 50.0755, lon: 14.4378, radius_km: 1000}}
        |> Events.list_events()
        |> Enum.map(& &1.external_id)

      refute "nowhere" in ids
    end

    test "measures the distance in metres on the spheroid" do
      [event] =
        Events.list_events(%{within: %{lat: 50.0755, lon: 14.4378, radius_km: 5}, type: "fire"})

      assert event.external_id == "praha"
      assert event.distance_m < 1.0
    end

    test "reports each event's distance from the centre" do
      events = Events.list_events(%{within: %{lat: 50.0755, lon: 14.4378, radius_km: 100}})
      beroun = Enum.find(events, &(&1.external_id == "beroun"))

      # Prague to Beroun is about 30 km; anything wildly different means the
      # measurement is not what we think it is.
      assert_in_delta beroun.distance_m / 1000, 30, 5
    end

    test "combines with the type filter" do
      events =
        Events.list_events(%{within: %{lat: 50.0755, lon: 14.4378, radius_km: 100}, type: "fire"})

      assert Enum.map(events, & &1.external_id) == ["praha"]
    end
  end

  describe "list_events/1" do
    setup do
      create(%{external_id: "a", type: "fire", occurred_at: ~U[2026-08-28 08:00:00Z]})
      create(%{external_id: "b", type: "flood", occurred_at: ~U[2026-08-28 10:00:00Z]})

      create(%{
        external_id: "c",
        type: "fire",
        located: false,
        occurred_at: ~U[2026-08-28 07:00:00Z]
      })

      :ok
    end

    test "returns everything, newest first" do
      assert ["b", "a", "c"] = Events.list_events() |> Enum.map(& &1.external_id) |> Enum.take(3)
    end

    test "filters by type" do
      assert ["a", "c"] =
               Events.list_events(%{type: "fire"}) |> Enum.map(& &1.external_id) |> Enum.sort()
    end

    test "`all` and no filter mean the same thing" do
      assert length(Events.list_events(%{type: "all"})) == length(Events.list_events())
    end

    test "keeps only located events when asked" do
      ids = Events.list_events(%{located: true}) |> Enum.map(& &1.external_id)
      refute "c" in ids
    end

    test "counts by type cover the whole catalog, including empty types" do
      counts = Events.count_by_type()

      assert counts["fire"] == 2
      assert counts["hazmat"] == 0
      assert Map.keys(counts) |> Enum.sort() == Enum.sort(CrisisMap.Catalog.event_type_ids())
    end
  end
end
