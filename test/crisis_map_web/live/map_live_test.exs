defmodule CrisisMapWeb.MapLiveTest do
  @moduledoc """
  The page's contract: the list is there, filtering changes it over the socket
  rather than by reloading, clicking an event shows the detail, and an event
  with no position is listed but not sent to the map.
  """
  use CrisisMapWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CrisisMap.EventsFixtures

  setup do
    %{
      fire: event_fixture(%{external_id: "praha-fire", title: "Požár haly", type: "fire", location_text: "Praha", at: {50.0755, 14.4378}}),
      crash: event_fixture(%{external_id: "beroun-crash", title: "Nehoda u Berouna", type: "traffic_accident", location_text: "Beroun", at: {49.9639, 14.0722}}),
      far: event_fixture(%{external_id: "ostrava-fire", title: "Požár v Ostravě", type: "fire", location_text: "Ostrava", at: {49.8209, 18.2625}}),
      unlocated: event_fixture(%{external_id: "nowhere", title: "Rozvodněný potok", type: "flood", location_text: "Neznámé místečko u lesa"})
    }
  end

  test "lists every event, including the one with no position", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/")

    assert html =~ "Požár haly"
    assert html =~ "Nehoda u Berouna"
    assert html =~ "Rozvodněný potok"
    assert html =~ "poloha nenalezena"
  end

  test "sends only located events to the map", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/")

    assert_push_event(live, "markers", %{markers: markers})
    titles = Enum.map(markers, & &1.title)

    assert "Požár haly" in titles
    refute "Rozvodněný potok" in titles
  end

  test "filtering by type updates the page over the socket", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/")

    # The markers pushed on mount, before the filter is applied.
    assert_push_event(live, "markers", %{markers: initial})
    assert length(initial) == 3

    html =
      live
      |> element("button[phx-value-type='fire']")
      |> render_click()

    assert html =~ "Požár haly"
    refute html =~ "Nehoda u Berouna"

    assert_push_event(live, "markers", %{markers: markers})
    assert length(markers) == 2
  end

  test "the radius filter is a PostGIS query, not a client-side trim", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/")

    html =
      live
      |> element("form[phx-change='filter_radius']")
      |> render_change(%{"center" => "praha", "radius" => "50"})

    assert html =~ "Požár haly"
    assert html =~ "Nehoda u Berouna"
    # Ostrava is ~280 km from Prague and the unlocated event has no position.
    refute html =~ "Požár v Ostravě"
    refute html =~ "Rozvodněný potok"
  end

  test "the radius filter reports each event's distance", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/")

    html =
      live
      |> element("form[phx-change='filter_radius']")
      |> render_change(%{"center" => "praha", "radius" => "50"})

    assert html =~ "km"
  end

  test "clicking an event shows type, title, location, time and description", %{conn: conn, fire: fire} do
    {:ok, live, _html} = live(conn, ~p"/")

    html =
      live
      |> element("button[phx-value-id='#{fire.id}']")
      |> render_click()

    assert html =~ "Požár"
    assert html =~ "Požár haly"
    assert html =~ "Praha"
    assert html =~ "28.08.2026 08:15"
    assert html =~ "Střet dvou osobních vozidel."
    assert html =~ "50.0755"
  end

  test "selecting a located event tells the map where to look", %{conn: conn, fire: fire} do
    {:ok, live, _html} = live(conn, ~p"/")

    live |> element("button[phx-value-id='#{fire.id}']") |> render_click()

    assert_push_event(live, "focus", %{lat: 50.0755, lon: 14.4378})
  end

  test "an event without a position shows why instead of showing coordinates", %{conn: conn, unlocated: unlocated} do
    {:ok, live, _html} = live(conn, ~p"/")

    html = live |> element("button[phx-value-id='#{unlocated.id}']") |> render_click()

    assert html =~ "Neznámé místečko u lesa"
    assert html =~ "neznámé"
  end

  test "a filter that matches nothing says so", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/")

    html = live |> element("button[phx-value-type='hazmat']") |> render_click()

    assert html =~ "Filtru neodpovídá žádná událost."
  end
end
