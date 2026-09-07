defmodule CrisisMap.Views do
  @moduledoc """
  The one JSON shape of a domain value.

  The API, the MCP tools, the cockpit and the map markers all render events
  through this module, so a field added to an event appears everywhere at once
  and cannot mean two different things on two surfaces. The shape keeps the
  source/derived split of the schema visible: derived facts sit under
  `geocoding`, never mixed in with what the source said.
  """

  alias CrisisMap.Catalog
  alias CrisisMap.Events.Event

  @doc "Renders one event."
  @spec event(Event.t()) :: map()
  def event(%Event{} = event) do
    %{
      id: event.id,
      external_id: event.external_id,
      title: event.title,
      description: event.description,
      type: event.type,
      type_label: Catalog.event_type_label(event.type),
      type_color: Catalog.event_type_color(event.type),
      location_text: event.location_text,
      occurred_at: event.occurred_at,
      located: Event.located?(event),
      latitude: Event.latitude(event),
      longitude: Event.longitude(event),
      distance_m: event.distance_m,
      geocoding: %{
        status: event.geocoding_status,
        display_name: event.geocoded_display_name,
        candidates: event.geocoding_candidates,
        confidence: event.geocoding_confidence,
        geocoded_at: event.geocoded_at
      },
      inserted_at: event.inserted_at
    }
  end

  @doc "Renders a list of events."
  @spec events([Event.t()]) :: [map()]
  def events(events), do: Enum.map(events, &event/1)

  @doc "Renders only what a map marker needs."
  @spec marker(Event.t()) :: map()
  def marker(%Event{} = event) do
    %{
      id: event.id,
      title: event.title,
      type: event.type,
      color: Catalog.event_type_color(event.type),
      latitude: Event.latitude(event),
      longitude: Event.longitude(event)
    }
  end

  @doc "Renders the markers of every located event in the list."
  @spec markers([Event.t()]) :: [map()]
  def markers(events) do
    events
    |> Enum.filter(&Event.located?/1)
    |> Enum.map(&marker/1)
  end
end
