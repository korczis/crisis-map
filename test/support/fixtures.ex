defmodule CrisisMap.Fixtures do
  @moduledoc "Raw source records, in the shape the dataset file uses."

  @doc "One raw record, overridable field by field."
  def raw(overrides \\ %{}) do
    %{
      "external_id" => "event-101",
      "title" => "Dopravní nehoda",
      "description" => "Střet dvou osobních vozidel.",
      "location" => "Beroun",
      "occurred_at" => "2026-08-28T08:15:00Z",
      "type" => "traffic_accident"
    }
    |> Map.merge(Map.new(overrides, fn {key, value} -> {to_string(key), value} end))
  end
end
