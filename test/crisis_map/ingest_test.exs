defmodule CrisisMap.IngestTest do
  @moduledoc """
  The three failure cases the exercise names — a duplicate record, a location
  nobody knows, and a geocoder that is down — plus the property that ties them
  together: one bad record never costs the run.
  """
  use CrisisMap.DataCase, async: true

  alias CrisisMap.Events
  alias CrisisMap.Events.Event
  alias CrisisMap.Fixtures
  alias CrisisMap.Geocoding.Fake
  alias CrisisMap.Ingest

  setup do
    Fake.known(%{"Beroun" => {49.9639, 14.0722}, "Praha" => {50.0755, 14.4378}})
    :ok
  end

  describe "duplicates" do
    test "the same record twice in one file produces one row" do
      report = Ingest.import_records([Fixtures.raw(), Fixtures.raw()])

      assert report.total == 2
      assert report.inserted == 1
      assert report.updated == 1
      assert Events.count_events() == 1
    end

    test "importing the same file twice produces one row and updates it" do
      first = Ingest.import_records([Fixtures.raw()])
      second = Ingest.import_records([Fixtures.raw(title: "Dopravní nehoda — upřesněno")])

      assert first.inserted == 1
      assert second.inserted == 0
      assert second.updated == 1
      assert Events.count_events() == 1
      assert Events.get_event_by_external_id("event-101").title == "Dopravní nehoda — upřesněno"
    end

    test "a re-import keeps the position it already resolved instead of asking again" do
      Ingest.import_records([Fixtures.raw()])

      # A geocoder that would fail if it were called at all.
      Fake.always({:error, :should_not_be_called})
      report = Ingest.import_records([Fixtures.raw()])

      assert report.reused == 1
      assert report.geocoder_errors == 0
      assert Events.get_event_by_external_id("event-101").geocoding_status == "ok"
    end

    test "regeocode: true asks again even when the position is known" do
      Ingest.import_records([Fixtures.raw()])
      Fake.known(%{"Beroun" => {50.0, 14.0}})

      report = Ingest.import_records([Fixtures.raw()], regeocode: true)

      assert report.reused == 0
      assert report.geocoded == 1
      assert Event.latitude(Events.get_event_by_external_id("event-101")) == 50.0
    end
  end

  describe "geocoding" do
    test "a resolved location is stored as a point" do
      Ingest.import_records([Fixtures.raw()])
      event = Events.get_event_by_external_id("event-101")

      assert event.geocoding_status == "ok"
      assert Event.located?(event)
      assert_in_delta Event.latitude(event), 49.9639, 0.0001
      assert_in_delta Event.longitude(event), 14.0722, 0.0001
    end

    test "an unknown location keeps the event, keeps the text and invents no coordinates" do
      report =
        Ingest.import_records([
          Fixtures.raw(external_id: "event-x", location: "Neznámé místečko u lesa")
        ])

      assert report.not_found == 1
      assert report.inserted == 1

      event = Events.get_event_by_external_id("event-x")
      assert event.location_text == "Neznámé místečko u lesa"
      assert event.geocoding_status == "not_found"
      assert event.geom == nil
      refute Event.located?(event)
    end

    test "a record with no location at all is skipped, not failed" do
      report = Ingest.import_records([Fixtures.raw(external_id: "event-y", location: "")])

      assert report.skipped == 1
      assert report.geocoder_errors == 0
      assert Events.get_event_by_external_id("event-y").geocoding_status == "skipped"
    end

    test "a geocoder that is down costs the record its position, not the import" do
      Fake.always({:error, {:transport, :timeout}})

      report =
        Ingest.import_records([
          Fixtures.raw(),
          Fixtures.raw(external_id: "event-102", location: "Praha")
        ])

      assert report.total == 2
      assert report.inserted == 2
      assert report.geocoder_errors == 2
      assert Events.count_events() == 2

      event = Events.get_event_by_external_id("event-101")
      assert event.geocoding_status == "error"
      assert event.location_text == "Beroun"
      assert event.geom == nil
    end

    test "one failing record does not stop the ones after it" do
      Fake.script(fn
        "Beroun" -> {:error, {:transport, :timeout}}
        "Praha" -> {:ok, %CrisisMap.Geocoding.Result{lat: 50.0755, lon: 14.4378, candidates: 1}}
        _ -> {:error, :not_found}
      end)

      report =
        Ingest.import_records([
          Fixtures.raw(),
          Fixtures.raw(external_id: "event-102", location: "Praha"),
          Fixtures.raw(external_id: "event-103", location: "Nikde")
        ])

      assert report.geocoder_errors == 1
      assert report.geocoded == 1
      assert report.not_found == 1
      assert Events.count_events() == 3
    end

    test "a position that disappears on re-geocoding is cleared, not left stale" do
      Ingest.import_records([Fixtures.raw()])
      assert Event.located?(Events.get_event_by_external_id("event-101"))

      Fake.always({:error, :not_found})
      Ingest.import_records([Fixtures.raw()], regeocode: true)

      event = Events.get_event_by_external_id("event-101")
      assert event.geocoding_status == "not_found"
      assert event.geom == nil
    end
  end

  describe "malformed input" do
    test "an unusable record is reported and the rest of the file still imports" do
      report =
        Ingest.import_records([
          Fixtures.raw(occurred_at: "yesterday"),
          Fixtures.raw(external_id: "event-102", location: "Praha")
        ])

      assert report.invalid == 1
      assert report.inserted == 1
      assert Events.count_events() == 1
      assert [%{subject: "event-101"}] = report.errors
    end
  end

  describe "import_file/1" do
    test "reads the bundled dataset and survives its deliberate defects" do
      assert {:ok, report} = Ingest.import_file()

      # The dataset ships with one repeated record and one unknown place.
      assert report.total == 13
      assert report.inserted == 12
      assert report.updated == 1
      assert Events.count_events() == 12
      assert report.not_found >= 1
    end

    test "a missing dataset is an error, not a crash" do
      assert {:error, :enoent} = Ingest.import_file(path: "priv/data/nope.json")
    end
  end
end
