defmodule CrisisMap.Catalog do
  @moduledoc """
  The canonical vocabulary of the domain.

  Event types and geocoding statuses are declared here once and nowhere else.
  Every other part of the system — the Ecto changeset validation, the LiveView
  filter, the JSON API, the OpenAPI document, the MCP tool schemas and the
  generated documentation — reads them from this module. A value that is not
  in this list does not exist anywhere in the system, and adding one here makes
  it appear in every projection without further edits.
  """

  @event_types [
    %{
      id: "traffic_accident",
      label: "Dopravní nehoda",
      description: "Road traffic collision.",
      color: "#dc2626"
    },
    %{
      id: "fire",
      label: "Požár",
      description: "Fire of any object or vegetation.",
      color: "#ea580c"
    },
    %{
      id: "flood",
      label: "Povodeň / zaplavení",
      description: "Flooding, flash flood, water damage.",
      color: "#2563eb"
    },
    %{
      id: "hazmat",
      label: "Nebezpečná látka",
      description: "Leak or presence of a hazardous substance.",
      color: "#7c3aed"
    },
    %{
      id: "technical_rescue",
      label: "Technická pomoc",
      description: "Technical assistance and rescue work.",
      color: "#0d9488"
    },
    %{
      id: "other",
      label: "Jiná událost",
      description: "Anything the source did not classify. Also the fallback for an unknown input type.",
      color: "#64748b"
    }
  ]

  @geocoding_statuses [
    %{
      id: "pending",
      description: "The record was stored but geocoding has not been attempted yet.",
      coordinates_known: false
    },
    %{
      id: "ok",
      description: "The geocoder returned a position for the location text.",
      coordinates_known: true
    },
    %{
      id: "not_found",
      description: "The geocoder ran and returned no candidate for the location text.",
      coordinates_known: false
    },
    %{
      id: "skipped",
      description: "There was no location text to geocode.",
      coordinates_known: false
    },
    %{
      id: "error",
      description: "The geocoder was unreachable or answered with an error. Retryable.",
      coordinates_known: false
    }
  ]

  @fallback_event_type "other"

  @doc "Every declared event type, in display order."
  @spec event_types() :: [map()]
  def event_types, do: @event_types

  @doc "The identifiers of every declared event type."
  @spec event_type_ids() :: [String.t()]
  def event_type_ids, do: Enum.map(@event_types, & &1.id)

  @doc "The event type used when the source sends something we do not know."
  @spec fallback_event_type() :: String.t()
  def fallback_event_type, do: @fallback_event_type

  @spec event_type(String.t()) :: map() | nil
  def event_type(id), do: Enum.find(@event_types, &(&1.id == id))

  @doc "Human label for a type identifier; the identifier itself if unknown."
  @spec event_type_label(String.t()) :: String.t()
  def event_type_label(id) do
    case event_type(id) do
      nil -> id
      type -> type.label
    end
  end

  @doc "Map colour for a type identifier."
  @spec event_type_color(String.t()) :: String.t()
  def event_type_color(id) do
    case event_type(id) do
      nil -> "#64748b"
      type -> type.color
    end
  end

  @spec geocoding_statuses() :: [map()]
  def geocoding_statuses, do: @geocoding_statuses

  @spec geocoding_status_ids() :: [String.t()]
  def geocoding_status_ids, do: Enum.map(@geocoding_statuses, & &1.id)

  @spec geocoding_status(String.t()) :: map() | nil
  def geocoding_status(id), do: Enum.find(@geocoding_statuses, &(&1.id == id))
end
