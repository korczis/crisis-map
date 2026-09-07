defmodule CrisisMapWeb.CockpitLive do
  @moduledoc """
  The cockpit: every capability, described and runnable in the browser.

  It is a projection like the others — the form for a capability is built from
  its declared parameters and the description shown is the one the OpenAPI
  document and the generated documentation use. It exists so that the state of
  the system, including a failing geocoder or an import that found nothing, is
  visible without a shell.
  """
  use CrisisMapWeb, :live_view

  alias CrisisMap.Capabilities
  alias CrisisMap.Capability

  @impl true
  def mount(_params, _session, socket) do
    capabilities = Capabilities.all()

    {:ok,
     assign(socket,
       page_title: "Cockpit",
       capabilities: capabilities,
       selected: List.first(capabilities),
       result: nil,
       duration_ms: nil,
       error: nil
     )}
  end

  @impl true
  def handle_event("select", %{"name" => name}, socket) do
    {:noreply, assign(socket, selected: Capabilities.get(name), result: nil, error: nil, duration_ms: nil)}
  end

  def handle_event("run", params, socket) do
    name = socket.assigns.selected.name
    params = Map.drop(params, ["_target"])

    {microseconds, outcome} = :timer.tc(fn -> Capabilities.dispatch(name, params) end)

    socket =
      case outcome do
        {:ok, data} ->
          assign(socket, result: encode(data), error: nil)

        {:error, {kind, message}} ->
          assign(socket, result: nil, error: "#{kind}: #{message}")

        {:error, reason} ->
          assign(socket, result: nil, error: inspect(reason))
      end

    {:noreply, assign(socket, duration_ms: Float.round(microseconds / 1000, 1))}
  end

  defp encode(data), do: Jason.encode!(data, pretty: true)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <header class="bg-base-100 border-b border-base-300 px-4 py-3 flex items-baseline gap-4">
        <h1 class="text-lg font-semibold">Cockpit</h1>
        <p class="text-sm opacity-70">{length(@capabilities)} schopností</p>
        <nav class="ml-auto text-sm flex gap-3">
          <.link navigate={~p"/"} class="link">Mapa</.link>
          <a href="/swagger" class="link">Swagger</a>
          <a href="/openapi.json" class="link">OpenAPI</a>
        </nav>
      </header>

      <div class="p-4 grid gap-4 lg:grid-cols-3">
        <section class="bg-base-100 rounded-box divide-y divide-base-300 overflow-hidden self-start">
          <button
            :for={capability <- @capabilities}
            phx-click="select"
            phx-value-name={capability.name}
            class={[
              "w-full text-left px-3 py-2 hover:bg-base-200",
              @selected.name == capability.name && "bg-base-200"
            ]}
          >
            <span class="font-mono text-sm">{capability.name}</span>
            <span class="block text-xs opacity-70">{capability.summary}</span>
          </button>
        </section>

        <section class="lg:col-span-2 space-y-4">
          <div class="bg-base-100 rounded-box p-4">
            <h2 class="font-mono text-base">{@selected.name}</h2>
            <p class="text-sm mt-2 whitespace-pre-line">{String.trim(@selected.description)}</p>

            <dl class="mt-3 text-xs font-mono grid grid-cols-[4rem_1fr] gap-y-1 opacity-80">
              <dt>http</dt>
              <dd>{Capability.http(@selected)}</dd>
              <dt>cli</dt>
              <dd>{Capability.cli(@selected)}</dd>
              <dt>mcp</dt>
              <dd>{Capability.tool_name(@selected)}</dd>
            </dl>

            <form phx-submit="run" class="mt-4 space-y-2">
              <label :for={param <- @selected.params} class="block">
                <span class="text-xs uppercase opacity-60">
                  {param.name}
                  <span :if={Map.get(param, :required, false)} class="text-error">*</span>
                  <span class="opacity-60">({param.type})</span>
                </span>
                <input
                  type="text"
                  name={param.name}
                  value={Map.get(param, :default) && to_string(Map.get(param, :default))}
                  placeholder={Map.get(param, :example) && to_string(Map.get(param, :example))}
                  class="input input-sm input-bordered w-full"
                />
                <span class="text-xs opacity-60">{param.description}</span>
              </label>
              <button class={["btn btn-sm", @selected.mutating && "btn-warning" || "btn-primary"]}>
                Spustit{if @selected.mutating, do: " (mění data)", else: ""}
              </button>
            </form>
          </div>

          <div :if={@error} class="bg-error/10 text-error rounded-box p-4 font-mono text-sm">
            {@error}
          </div>

          <div :if={@result} class="bg-base-100 rounded-box p-4">
            <p class="text-xs opacity-60 mb-2">odpověď za {@duration_ms} ms</p>
            <pre class="text-xs overflow-auto max-h-[28rem]"><%= @result %></pre>
          </div>
        </section>
      </div>
    </div>
    """
  end
end
