defmodule CrisisMap.Ingest.NormalizerTest do
  @moduledoc """
  Normalisation is where a source record becomes a domain value. These tests
  pin down the two rules that matter: nothing is invented, and nothing is
  dropped because the source was untidy.
  """
  use ExUnit.Case, async: true

  alias CrisisMap.Fixtures
  alias CrisisMap.Ingest.Normalizer

  describe "normalize/1" do
    test "maps a well-formed record onto domain attributes" do
      assert {:ok, attrs} = Normalizer.normalize(Fixtures.raw())

      assert attrs.external_id == "event-101"
      assert attrs.title == "Dopravní nehoda"
      assert attrs.type == "traffic_accident"
      assert attrs.location_text == "Beroun"
      assert attrs.occurred_at == ~U[2026-08-28 08:15:00Z]
    end

    test "trims surrounding whitespace instead of storing it" do
      assert {:ok, attrs} = Normalizer.normalize(Fixtures.raw(location: "  Praha  "))
      assert attrs.location_text == "Praha"
    end

    test "treats an empty location as no location, not as an empty place name" do
      assert {:ok, attrs} = Normalizer.normalize(Fixtures.raw(location: "   "))
      assert attrs.location_text == nil
    end

    test "accepts atom-keyed records, so a fixture and a JSON file take one path" do
      assert {:ok, attrs} =
               Normalizer.normalize(%{
                 external_id: "event-900",
                 title: "Test",
                 occurred_at: ~U[2026-08-28 08:15:00Z],
                 type: "fire",
                 location: "Brno"
               })

      assert attrs.external_id == "event-900"
      assert attrs.occurred_at == ~U[2026-08-28 08:15:00Z]
    end

    test "canonicalises a type the source wrote differently" do
      assert {:ok, %{type: "hazmat"}} = Normalizer.normalize(Fixtures.raw(type: "HAZMAT"))

      assert {:ok, %{type: "traffic_accident"}} =
               Normalizer.normalize(Fixtures.raw(type: "Traffic Accident"))
    end

    test "files an unknown type under the catalog fallback rather than losing the event" do
      assert {:ok, %{type: "other"}} =
               Normalizer.normalize(Fixtures.raw(type: "meteorite_strike"))

      assert {:ok, %{type: "other"}} = Normalizer.normalize(Fixtures.raw() |> Map.delete("type"))
    end

    test "rejects a record with no identity, no title or no time" do
      assert {:error, {:missing, :external_id}} =
               Normalizer.normalize(Fixtures.raw(external_id: ""))

      assert {:error, {:missing, :title}} =
               Normalizer.normalize(Fixtures.raw() |> Map.delete("title"))

      assert {:error, {:missing, :occurred_at}} =
               Normalizer.normalize(Fixtures.raw() |> Map.delete("occurred_at"))
    end

    test "rejects an unparsable timestamp instead of guessing one" do
      assert {:error, {:invalid, :occurred_at, "yesterday"}} =
               Normalizer.normalize(Fixtures.raw(occurred_at: "yesterday"))
    end
  end
end
