defmodule CrisisMapWeb.CapabilityController do
  @moduledoc """
  The HTTP projection of the capability registry.

  There is one action for every capability because there is one action, full
  stop: the route carries the capability name, this controller casts the
  parameters through the capability's own schema and calls the registry. A new
  API endpoint is therefore a new registry entry and nothing else — no
  controller, no view, no route to add by hand and forget to document.
  """
  use CrisisMapWeb, :controller

  alias CrisisMap.Capabilities

  def dispatch(conn, params) do
    name = conn.assigns.capability

    case Capabilities.dispatch(name, params) do
      {:ok, data} ->
        json(conn, %{capability: name, data: data})

      {:error, {kind, message}} ->
        conn
        |> put_status(status_for(kind))
        |> json(%{capability: name, error: %{kind: kind, message: to_string(message)}})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{capability: name, error: %{kind: :internal, message: inspect(reason)}})
    end
  end

  defp status_for(:not_found), do: :not_found
  defp status_for(:bad_request), do: :bad_request
  defp status_for(:unprocessable), do: :unprocessable_entity
  defp status_for(_), do: :internal_server_error
end
