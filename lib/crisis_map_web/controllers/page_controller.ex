defmodule CrisisMapWeb.PageController do
  use CrisisMapWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
