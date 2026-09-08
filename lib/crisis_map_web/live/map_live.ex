defmodule CrisisMapWeb.MapLive do
  @moduledoc """
  The operator's page: a map, the list behind it, and the detail of whatever
  is selected.

  The division of labour is deliberate and is the answer to "what runs where":

    * the server holds all state — the active filters, the result of the
      query, the selected event — and does every bit of selection in the
      database, spatial predicate included;
    * the browser holds no application state. Leaflet is a rendering device:
      it is handed a list of markers and told where to look, and the only
      thing it sends back is "the user clicked marker N".

  A filter change is therefore a database query and a diff over the socket,
  never a page reload and never a client-side filtering of a preloaded list.
  """
  use CrisisMapWeb, :live_view

  alias CrisisMap.Catalog
  alias CrisisMap.Events
  alias CrisisMap.Events.Event
  alias CrisisMap.Views

  @radius_options [25, 50, 100, 200]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        page_title: "Krizová mapa",
        type: "all",
        center_id: "praha",
        radius_km: nil,
        selected: nil,
        event_types: Catalog.event_types(),
        reference_points: Catalog.reference_points(),
        radius_options: @radius_options
      )
      |> load_events()

    {:ok, socket}
  end

  @impl true
  def handle_event("filter_type", %{"type" => type}, socket) do
    {:noreply, socket |> assign(type: type) |> keep_selection() |> load_events()}
  end

  def handle_event("filter_radius", %{"radius" => radius, "center" => center_id}, socket) do
    radius_km =
      case radius do
        "" -> nil
        value -> String.to_integer(value)
      end

    {:noreply,
     socket
     |> assign(radius_km: radius_km, center_id: center_id)
     |> keep_selection()
     |> load_events()}
  end

  def handle_event("select", %{"id" => id}, socket) do
    {:noreply, select(socket, id)}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, selected: nil)}
  end

  defp select(socket, id) when is_binary(id), do: select(socket, String.to_integer(id))

  defp select(socket, id) do
    case Enum.find(socket.assigns.events, &(&1.id == id)) do
      nil ->
        socket

      event ->
        socket
        |> assign(selected: event)
        |> focus(event)
    end
  end

  defp focus(socket, %Event{} = event) do
    if Event.located?(event) do
      push_event(socket, "focus", %{lat: Event.latitude(event), lon: Event.longitude(event)})
    else
      socket
    end
  end

  # Re-running the query can drop the selected event out of the result; when
  # that happens the detail panel closes rather than showing something the
  # filter says is not there.
  defp keep_selection(socket), do: socket

  defp load_events(socket) do
    %{type: type, radius_km: radius_km, center_id: center_id} = socket.assigns
    center = Catalog.reference_point(center_id)

    filters =
      %{type: type}
      |> maybe_within(center, radius_km)

    events = Events.list_events(filters)
    located = Enum.filter(events, &Event.located?/1)

    selected =
      case socket.assigns.selected do
        nil -> nil
        %Event{id: id} -> Enum.find(events, &(&1.id == id))
      end

    socket
    |> assign(
      events: events,
      selected: selected,
      located_count: length(located),
      total_count: length(events),
      stats: Events.count_by_geocoding_status()
    )
    |> push_event("markers", %{
      markers: Views.markers(events),
      circle: circle(center, radius_km)
    })
  end

  defp maybe_within(filters, _center, nil), do: filters
  defp maybe_within(filters, nil, _radius_km), do: filters

  defp maybe_within(filters, center, radius_km) do
    Map.put(filters, :within, %{lat: center.lat, lon: center.lon, radius_km: radius_km})
  end

  defp circle(_center, nil), do: nil
  defp circle(nil, _radius_km), do: nil
  defp circle(center, radius_km), do: %{lat: center.lat, lon: center.lon, radius_m: radius_km * 1000}

  defp distance(%Event{distance_m: nil}), do: nil
  defp distance(%Event{distance_m: metres}), do: "#{Float.round(metres / 1000, 1)} km"

  defp when_occurred(%DateTime{} = at) do
    Calendar.strftime(at, "%d.%m.%Y %H:%M")
  end

  defp status_note(%Event{geocoding_status: "ok"}), do: nil
  defp status_note(%Event{geocoding_status: "not_found"}), do: "poloha nenalezena"
  defp status_note(%Event{geocoding_status: "error"}), do: "geokodér nedostupný"
  defp status_note(%Event{geocoding_status: "skipped"}), do: "bez uvedeného místa"
  defp status_note(%Event{geocoding_status: "pending"}), do: "čeká na geokódování"
  defp status_note(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <header class="bg-base-100 border-b border-base-300 px-4 py-3">
        <div class="flex flex-wrap items-baseline gap-x-4 gap-y-1">
          <h1 class="text-lg font-semibold">Krizová mapa</h1>
          <p class="text-sm opacity-70">
            {@total_count} událostí, {@located_count} se známou polohou
          </p>
          <nav class="ml-auto text-sm flex gap-3">
            <.link navigate={~p"/cockpit"} class="link">Cockpit</.link>
            <a href="/swagger" class="link">API</a>
          </nav>
        </div>
      </header>

      <div class="p-4 space-y-4">
        <section class="bg-base-100 rounded-box p-3 flex flex-wrap gap-4 items-end">
          <div>
            <p class="text-xs uppercase opacity-60 mb-1">Typ události</p>
            <div class="flex flex-wrap gap-1">
              <button
                phx-click="filter_type"
                phx-value-type="all"
                class={["btn btn-xs", @type == "all" && "btn-primary"]}
              >
                Vše
              </button>
              <button
                :for={type <- @event_types}
                phx-click="filter_type"
                phx-value-type={type.id}
                class={["btn btn-xs", @type == type.id && "btn-primary"]}
              >
                <span class="w-2 h-2 rounded-full" style={"background: #{type.color}"}></span>
                {type.label}
              </button>
            </div>
          </div>

          <form id="radius-filter" phx-change="filter_radius" class="flex gap-2 items-end">
            <label class="text-xs uppercase opacity-60">
              Okolí bodu
              <select name="center" class="select select-xs select-bordered block mt-1">
                <option :for={point <- @reference_points} value={point.id} selected={point.id == @center_id}>
                  {point.label}
                </option>
              </select>
            </label>
            <label class="text-xs uppercase opacity-60">
              Poloměr
              <select name="radius" class="select select-xs select-bordered block mt-1">
                <option value="" selected={is_nil(@radius_km)}>bez omezení</option>
                <option :for={km <- @radius_options} value={km} selected={km == @radius_km}>
                  do {km} km
                </option>
              </select>
            </label>
          </form>
        </section>

        <div class="grid gap-4 lg:grid-cols-3">
          <div class="lg:col-span-2 space-y-4">
            <div
              id="crisis-map"
              phx-hook=".Leaflet"
              phx-update="ignore"
              class="w-full h-[420px] rounded-box border border-base-300 bg-base-100"
            >
            </div>

            <div :if={@selected} class="bg-base-100 rounded-box p-4">
              <div class="flex items-start gap-3">
                <span
                  class="mt-1 w-3 h-3 rounded-full shrink-0"
                  style={"background: #{Catalog.event_type_color(@selected.type)}"}
                >
                </span>
                <div class="flex-1">
                  <p class="text-xs uppercase opacity-60">
                    {Catalog.event_type_label(@selected.type)}
                  </p>
                  <h2 class="text-base font-semibold">{@selected.title}</h2>
                  <dl class="mt-2 text-sm grid grid-cols-[8rem_1fr] gap-y-1">
                    <dt class="opacity-60">Lokalita</dt>
                    <dd>
                      {@selected.location_text || "—"}
                      <span :if={status_note(@selected)} class="badge badge-sm badge-warning ml-1">
                        {status_note(@selected)}
                      </span>
                    </dd>
                    <dt class="opacity-60">Čas</dt>
                    <dd>{when_occurred(@selected.occurred_at)}</dd>
                    <dt class="opacity-60">Souřadnice</dt>
                    <dd>
                      <%= if Event.located?(@selected) do %>
                        {Float.round(Event.latitude(@selected), 5)},
                        {Float.round(Event.longitude(@selected), 5)}
                        <span :if={@selected.geocoding_candidates && @selected.geocoding_candidates > 1} class="opacity-60">
                          ({@selected.geocoding_candidates} kandidátů, skóre {@selected.geocoding_confidence})
                        </span>
                      <% else %>
                        neznámé
                      <% end %>
                    </dd>
                    <dt class="opacity-60">Zdroj</dt>
                    <dd class="font-mono text-xs">{@selected.external_id}</dd>
                    <dt :if={distance(@selected)} class="opacity-60">Vzdálenost</dt>
                    <dd :if={distance(@selected)}>{distance(@selected)}</dd>
                  </dl>
                  <p class="mt-3 text-sm">{@selected.description}</p>
                </div>
                <button phx-click="clear_selection" class="btn btn-ghost btn-xs">zavřít</button>
              </div>
            </div>
          </div>

          <section class="bg-base-100 rounded-box divide-y divide-base-300 overflow-hidden self-start">
            <p class="px-3 py-2 text-xs uppercase opacity-60">Seznam událostí</p>
            <button
              :for={event <- @events}
              phx-click="select"
              phx-value-id={event.id}
              class={[
                "w-full text-left px-3 py-2 hover:bg-base-200",
                @selected && @selected.id == event.id && "bg-base-200"
              ]}
            >
              <span class="flex items-center gap-2">
                <span
                  class="w-2.5 h-2.5 rounded-full shrink-0"
                  style={"background: #{Catalog.event_type_color(event.type)}"}
                >
                </span>
                <span class="text-sm font-medium flex-1">{event.title}</span>
                <span class="text-xs opacity-60">{when_occurred(event.occurred_at)}</span>
              </span>
              <span class="block text-xs opacity-70 pl-4.5">
                {event.location_text || "místo neuvedeno"}
                <span :if={status_note(event)} class="text-warning">· {status_note(event)}</span>
                <span :if={distance(event)}>· {distance(event)}</span>
              </span>
            </button>
            <p :if={@events == []} class="px-3 py-6 text-sm opacity-60 text-center">
              Filtru neodpovídá žádná událost.
            </p>
          </section>
        </div>
      </div>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".Leaflet">
      // The whole of the client. It renders what the server sends and reports
      // clicks back; it never filters, sorts or stores events.
      export default {
        mounted() {
          this.map = L.map(this.el).setView([49.8, 15.5], 7);
          L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
            attribution: "© OpenStreetMap",
            maxZoom: 18
          }).addTo(this.map);

          this.markerLayer = L.layerGroup().addTo(this.map);
          this.circleLayer = L.layerGroup().addTo(this.map);

          this.handleEvent("markers", ({markers, circle}) => this.draw(markers, circle));
          this.handleEvent("focus", ({lat, lon}) => this.map.setView([lat, lon], 11));

          if (this.pending) { this.draw(this.pending.markers, this.pending.circle); }
        },

        draw(markers, circle) {
          if (!this.map) { this.pending = {markers, circle}; return; }

          this.markerLayer.clearLayers();
          this.circleLayer.clearLayers();

          markers.forEach((marker) => {
            L.circleMarker([marker.latitude, marker.longitude], {
              radius: 8,
              color: "#ffffff",
              weight: 2,
              fillColor: marker.color,
              fillOpacity: 0.9
            })
              .bindTooltip(marker.title)
              .on("click", () => this.pushEvent("select", {id: String(marker.id)}))
              .addTo(this.markerLayer);
          });

          if (circle) {
            L.circle([circle.lat, circle.lon], {
              radius: circle.radius_m,
              color: "#2563eb",
              weight: 1,
              fillOpacity: 0.05
            }).addTo(this.circleLayer);
            this.map.fitBounds(L.circle([circle.lat, circle.lon], {radius: circle.radius_m}).getBounds());
          }
        }
      }
    </script>
    """
  end
end
