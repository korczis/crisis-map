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
    {:noreply,
     assign(socket, selected: Capabilities.get(name), result: nil, error: nil, duration_ms: nil)}
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
    <Layouts.app flash={@flash} active={:cockpit}>
      <.page_header crumbs={[%{label: "Krizová mapa", navigate: ~p"/"}, %{label: "Cockpit"}]}>
        Cockpit
        <:subtitle>{length(@capabilities)} schopností</:subtitle>
        <:actions>
          <.button navigate={~p"/"}>
            <.icon name="hero-map" class="size-4" /> Mapa
          </.button>
          <.button href="/swagger">
            <.icon name="hero-book-open" class="size-4" /> Swagger
          </.button>
          <.button href="/openapi.json">
            <.icon name="hero-code-bracket" class="size-4" /> OpenAPI
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 p-4 lg:grid-cols-3">
        <section class="self-start overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <div class="divide-y divide-gray-200 dark:divide-gray-700">
            <button
              :for={capability <- @capabilities}
              type="button"
              phx-click="select"
              phx-value-name={capability.name}
              class={[
                "w-full cursor-pointer px-4 py-3 text-left hover:bg-gray-100 dark:hover:bg-gray-700",
                @selected.name == capability.name && "bg-gray-100 dark:bg-gray-700"
              ]}
            >
              <span class="font-mono text-sm font-medium text-gray-900 dark:text-white">
                {capability.name}
              </span>
              <span class="block text-xs text-gray-500 dark:text-gray-400">
                {capability.summary}
              </span>
            </button>
          </div>
        </section>

        <section class="space-y-4 lg:col-span-2">
          <div class="rounded-lg border border-gray-200 bg-white p-4 shadow-sm sm:p-6 dark:border-gray-700 dark:bg-gray-800">
            <h2 class="font-mono text-xl font-bold text-gray-900 dark:text-white">
              {@selected.name}
            </h2>
            <p class="mt-2 whitespace-pre-line text-sm text-gray-500 dark:text-gray-400">
              {String.trim(@selected.description)}
            </p>

            <dl class="mt-4 grid grid-cols-[4rem_1fr] gap-y-1 rounded-lg bg-gray-50 p-3 font-mono text-xs text-gray-900 dark:bg-gray-700 dark:text-gray-200">
              <dt class="text-gray-500 dark:text-gray-400">http</dt>
              <dd>{Capability.http(@selected)}</dd>
              <dt class="text-gray-500 dark:text-gray-400">cli</dt>
              <dd>{Capability.cli(@selected)}</dd>
              <dt class="text-gray-500 dark:text-gray-400">mcp</dt>
              <dd>{Capability.tool_name(@selected)}</dd>
            </dl>

            <form phx-submit="run" class="mt-6 space-y-4">
              <label :for={param <- @selected.params} class="block">
                <span class="mb-2 block text-sm font-medium text-gray-900 dark:text-white">
                  {param.name}
                  <span :if={Map.get(param, :required, false)} class="text-red-600 dark:text-red-500">
                    *
                  </span>
                  <span class="font-normal text-gray-500 dark:text-gray-400">({param.type})</span>
                </span>
                <input
                  type="text"
                  name={param.name}
                  value={Map.get(param, :default) && to_string(Map.get(param, :default))}
                  placeholder={Map.get(param, :example) && to_string(Map.get(param, :example))}
                  class={input_class()}
                />
                <span class="mt-1 block text-xs text-gray-500 dark:text-gray-400">
                  {param.description}
                </span>
              </label>
              <button class={[
                button_base(),
                (@selected.mutating &&
                   "text-white bg-yellow-500 hover:bg-yellow-600 focus:ring-yellow-300 dark:focus:ring-yellow-900") ||
                  "text-white bg-primary-700 hover:bg-primary-800 focus:ring-primary-300 dark:bg-primary-600 dark:hover:bg-primary-700 dark:focus:ring-primary-800"
              ]}>
                Spustit{if @selected.mutating, do: " (mění data)", else: ""}
              </button>
            </form>
          </div>

          <div
            :if={@error}
            role="alert"
            class="rounded-lg border border-red-300 bg-red-50 p-4 font-mono text-sm text-red-800 dark:border-red-800 dark:bg-gray-800 dark:text-red-400"
          >
            {@error}
          </div>

          <div
            :if={@result}
            class="rounded-lg border border-gray-200 bg-white p-4 shadow-sm sm:p-6 dark:border-gray-700 dark:bg-gray-800"
          >
            <p class="mb-2 text-xs text-gray-500 dark:text-gray-400">odpověď za {@duration_ms} ms</p>
            <pre class="max-h-[28rem] overflow-auto rounded-lg bg-gray-50 p-3 text-xs text-gray-900 dark:bg-gray-900 dark:text-gray-200"><%= @result %></pre>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
