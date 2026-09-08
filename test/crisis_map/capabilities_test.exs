defmodule CrisisMap.CapabilitiesTest do
  @moduledoc """
  One test per declared capability, naming it, plus the behaviour of the
  dispatcher every surface goes through.

  Naming each capability here is what the doctrine gate "a test names it"
  checks for: a capability that nobody bothered to exercise cannot quietly
  ship on four surfaces at once.
  """
  use CrisisMap.DataCase, async: true

  import CrisisMap.EventsFixtures

  alias CrisisMap.Capabilities
  alias CrisisMap.Geocoding.Fake

  describe "dispatch/2" do
    test "rejects an unknown capability" do
      assert {:error, {:not_found, _}} = Capabilities.dispatch("events.explode")
    end

    test "rejects a missing required parameter with the capability's own message" do
      assert {:error, {:bad_request, "missing required parameter id"}} =
               Capabilities.dispatch("events.get", %{})
    end

    test "rejects a parameter of the wrong type" do
      assert {:error, {:bad_request, message}} =
               Capabilities.dispatch("events.near", %{lat: "north", lon: 14.4, radius_km: 10})

      assert message =~ "is not a number"
    end

    test "accepts string keys and string values, as HTTP and the shell deliver them" do
      event_fixture(%{external_id: "event-101", at: {50.0, 14.0}})

      assert {:ok, [event]} =
               Capabilities.dispatch("events.list", %{
                 "type" => "traffic_accident",
                 "limit" => "5"
               })

      assert event.external_id == "event-101"
    end

    test "applies a declared default when the parameter is absent" do
      # ingest.import declares regeocode: false.
      Fake.always({:error, :not_found})
      assert {:ok, report} = Capabilities.dispatch("ingest.import", %{})
      assert report.reused == 0
    end
  end

  describe "events.list" do
    test "returns stored events and honours the located filter" do
      event_fixture(%{external_id: "located", at: {50.0, 14.0}})
      event_fixture(%{external_id: "unlocated"})

      assert {:ok, all} = Capabilities.dispatch("events.list", %{})
      assert length(all) == 2

      assert {:ok, [only]} = Capabilities.dispatch("events.list", %{located: true})
      assert only.external_id == "located"
      assert only.located
    end
  end

  describe "events.get" do
    test "finds an event by external id and by database id" do
      event = event_fixture(%{external_id: "event-101", at: {50.0, 14.0}})

      assert {:ok, by_external} = Capabilities.dispatch("events.get", %{id: "event-101"})
      assert {:ok, by_id} = Capabilities.dispatch("events.get", %{id: to_string(event.id)})
      assert by_external.id == by_id.id
    end

    test "reports a missing event as not found rather than crashing" do
      assert {:error, {:not_found, _}} = Capabilities.dispatch("events.get", %{id: "nope"})
    end
  end

  describe "events.near" do
    test "returns events inside the radius, nearest first, with distances" do
      event_fixture(%{external_id: "praha", at: {50.0755, 14.4378}})
      event_fixture(%{external_id: "beroun", at: {49.9639, 14.0722}})
      event_fixture(%{external_id: "ostrava", at: {49.8209, 18.2625}})

      assert {:ok, events} =
               Capabilities.dispatch("events.near", %{lat: 50.0755, lon: 14.4378, radius_km: 50})

      assert Enum.map(events, & &1.external_id) == ["praha", "beroun"]
      assert Enum.all?(events, &is_float(&1.distance_m))
    end
  end

  describe "events.stats" do
    test "counts by type and by geocoding status" do
      event_fixture(%{external_id: "a", type: "fire", at: {50.0, 14.0}})
      event_fixture(%{external_id: "b", type: "fire"})

      assert {:ok, stats} = Capabilities.dispatch("events.stats", %{})
      assert stats.total == 2
      assert stats.by_type["fire"] == 2
      assert stats.by_geocoding_status["ok"] == 1
      assert stats.by_geocoding_status["not_found"] == 1
    end
  end

  describe "catalog.event_types and catalog.geocoding_statuses" do
    test "expose the vocabulary every surface shares" do
      assert {:ok, types} = Capabilities.dispatch("catalog.event_types", %{})
      assert Enum.map(types, & &1.id) == CrisisMap.Catalog.event_type_ids()

      assert {:ok, statuses} = Capabilities.dispatch("catalog.geocoding_statuses", %{})
      assert Enum.map(statuses, & &1.id) == CrisisMap.Catalog.geocoding_status_ids()
    end
  end

  describe "geocoding.lookup" do
    test "reports a found place with its candidate count and score" do
      Fake.known(%{"Beroun" => {49.9639, 14.0722}})

      assert {:ok, result} = Capabilities.dispatch("geocoding.lookup", %{query: "Beroun"})
      assert result.status == "ok"
      assert result.latitude == 49.9639
      assert result.candidates == 1
    end

    test "reports an unknown place as not found, with no coordinates" do
      Fake.known(%{})

      assert {:ok, %{status: "not_found"} = result} =
               Capabilities.dispatch("geocoding.lookup", %{query: "Neznámé místečko u lesa"})

      refute Map.has_key?(result, :latitude)
    end

    test "reports an unreachable geocoder as an error rather than failing the call" do
      Fake.always({:error, {:transport, :timeout}})

      assert {:ok, %{status: "error", reason: reason}} =
               Capabilities.dispatch("geocoding.lookup", %{query: "Beroun"})

      assert reason =~ "timeout"
    end
  end

  describe "geocoding.status" do
    test "answers which adapter is in use and whether it is reachable" do
      assert {:ok, %{reachable: true, adapter: "fake"}} =
               Capabilities.dispatch("geocoding.status", %{})
    end
  end

  describe "ingest.import" do
    test "imports the bundled dataset and reports what happened to each record" do
      Fake.known(%{"Beroun" => {49.9639, 14.0722}})

      assert {:ok, report} = Capabilities.dispatch("ingest.import", %{})
      assert report.total == 13
      assert report.inserted == 12
      assert report.geocoded >= 1
      assert report.not_found >= 1
    end

    test "reports a missing dataset as unprocessable rather than raising" do
      assert {:error, {:unprocessable, reason}} =
               Capabilities.dispatch("ingest.import", %{path: "priv/data/nope.json"})

      assert reason =~ "enoent"
    end
  end

  describe "system.capabilities" do
    test "describes every capability, itself included" do
      assert {:ok, described} = Capabilities.dispatch("system.capabilities", %{})

      assert Enum.map(described, & &1.name) == Capabilities.names()
      assert Enum.any?(described, &(&1.name == "system.capabilities"))
      assert Enum.all?(described, &(&1.http != "" and &1.cli != "" and &1.mcp_tool != ""))
    end
  end

  describe "system.health" do
    test "reports the database, PostGIS and the geocoder" do
      assert {:ok, health} = Capabilities.dispatch("system.health", %{})

      assert health.database.reachable
      assert health.database.postgis =~ "USE_GEOS"
      assert health.geocoder.reachable
    end
  end
end
