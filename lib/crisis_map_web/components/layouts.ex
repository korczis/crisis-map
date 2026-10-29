defmodule CrisisMapWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use CrisisMapWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders the application shell, adapted from the Flowbite Pro admin dashboard:
  a fixed navbar, a sidebar drawer (always open from `lg` up, toggled by
  Flowbite's drawer on smaller screens) and the main content on the gray page.

  Pages put a `<.page_header>` and their content inside it.

  ## Examples

      <Layouts.app flash={@flash} active={:map}>
        <.page_header crumbs={[%{label: "Mapa"}]}>Krizová mapa</.page_header>
        <div class="p-4">…</div>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :active, :atom, default: nil, doc: "the sidebar item of the current page"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 text-gray-900 antialiased dark:bg-gray-900 dark:text-white">
      <nav class="fixed top-0 z-50 w-full border-b border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
        <div class="px-3 py-3 lg:px-5 lg:pl-3">
          <div class="flex items-center justify-between">
            <div class="flex items-center justify-start">
              <button
                type="button"
                data-drawer-target="sidebar"
                data-drawer-toggle="sidebar"
                aria-controls="sidebar"
                class="mr-2 cursor-pointer rounded-lg p-2 text-gray-600 hover:bg-gray-100 hover:text-gray-900 focus:bg-gray-100 focus:ring-2 focus:ring-gray-100 lg:hidden dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-white dark:focus:bg-gray-700 dark:focus:ring-gray-700"
              >
                <span class="sr-only">{gettext("Toggle sidebar")}</span>
                <.icon name="hero-bars-3" class="size-6" />
              </button>
              <.link navigate={~p"/"} class="mr-4 flex items-center">
                <img src={~p"/images/logo.svg"} class="mr-3 h-8" alt="" />
                <span class="self-center whitespace-nowrap text-xl font-semibold sm:text-2xl dark:text-white">
                  Krizová mapa
                </span>
              </.link>
            </div>
            <div class="flex items-center">
              <.theme_toggle />
            </div>
          </div>
        </div>
      </nav>

      <aside
        id="sidebar"
        aria-label="Sidebar"
        phx-mounted={JS.ignore_attributes(["class", "aria-hidden", "aria-modal", "role"])}
        class="fixed top-0 left-0 z-40 h-screen w-64 -translate-x-full border-r border-gray-200 bg-white pt-16 transition-transform lg:translate-x-0 dark:border-gray-700 dark:bg-gray-800"
      >
        <div class="h-full overflow-y-auto bg-white px-3 py-5 dark:bg-gray-800">
          <ul class="space-y-2 pb-2">
            <li>
              <.sidebar_link navigate={~p"/"} icon="hero-map" active={@active == :map}>
                Mapa
              </.sidebar_link>
            </li>
            <li>
              <.sidebar_link
                navigate={~p"/cockpit"}
                icon="hero-command-line"
                active={@active == :cockpit}
              >
                Cockpit
              </.sidebar_link>
            </li>
          </ul>
          <ul class="mt-4 space-y-2 border-t border-gray-200 pt-4 dark:border-gray-700">
            <li>
              <.sidebar_link href="/swagger" icon="hero-book-open">API (Swagger)</.sidebar_link>
            </li>
            <li>
              <.sidebar_link href="/openapi.json" icon="hero-code-bracket">OpenAPI</.sidebar_link>
            </li>
          </ul>
        </div>
      </aside>

      <div id="main-content" class="relative min-h-screen pt-16 lg:ml-64">
        <main>
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :navigate, :string, default: nil, doc: "a LiveView path"
  attr :href, :string, default: nil, doc: "a plain link, for pages outside the LiveViews"
  attr :icon, :string, required: true
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  defp sidebar_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      href={@href}
      aria-current={@active && "page"}
      class={[
        "group flex items-center rounded-lg p-2 text-base font-normal text-gray-900 hover:bg-gray-100 dark:text-gray-200 dark:hover:bg-gray-700",
        @active && "bg-gray-100 dark:bg-gray-700"
      ]}
    >
      <.icon
        name={@icon}
        class="size-6 shrink-0 text-gray-500 transition duration-75 group-hover:text-gray-900 dark:text-gray-400 dark:group-hover:text-white"
      />
      <span class="ml-3 flex-1 whitespace-nowrap">{render_slot(@inner_block)}</span>
    </.link>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides the system / light / dark theme toggle, styled as the Pro navbar's
  icon buttons; the active choice holds the hover colour.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div
      class="inline-flex items-center rounded-lg border border-gray-200 p-0.5 dark:border-gray-700"
      role="group"
      aria-label={gettext("Theme")}
    >
      <button
        type="button"
        class={[
          theme_button_class(),
          "[[data-theme-source=system]_&]:bg-gray-100 [[data-theme-source=system]_&]:text-gray-900",
          "dark:[[data-theme-source=system]_&]:bg-gray-700 dark:[[data-theme-source=system]_&]:text-white"
        ]}
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        title={gettext("System theme")}
      >
        <span class="sr-only">{gettext("System theme")}</span>
        <.icon name="hero-computer-desktop-micro" class="size-4" />
      </button>

      <button
        type="button"
        class={[
          theme_button_class(),
          "[[data-theme=light][data-theme-source=user]_&]:bg-gray-100",
          "[[data-theme=light][data-theme-source=user]_&]:text-gray-900"
        ]}
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        title={gettext("Light theme")}
      >
        <span class="sr-only">{gettext("Light theme")}</span>
        <.icon name="hero-sun-micro" class="size-4" />
      </button>

      <button
        type="button"
        class={[
          theme_button_class(),
          "[[data-theme=dark][data-theme-source=user]_&]:bg-gray-700",
          "[[data-theme=dark][data-theme-source=user]_&]:text-white"
        ]}
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        title={gettext("Dark theme")}
      >
        <span class="sr-only">{gettext("Dark theme")}</span>
        <.icon name="hero-moon-micro" class="size-4" />
      </button>
    </div>
    """
  end

  defp theme_button_class,
    do:
      "flex cursor-pointer rounded-md p-2 text-gray-500 hover:bg-gray-100 hover:text-gray-900 focus:outline-none focus:ring-2 focus:ring-gray-200 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-white dark:focus:ring-gray-700"
end
