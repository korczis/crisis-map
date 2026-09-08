defmodule CrisisMap.Repo do
  @moduledoc """
  The PostgreSQL/PostGIS connection.

  Configured with `CrisisMap.PostgresTypes` so that Postgrex understands the
  geography wire format; nothing above `CrisisMap.Events` uses this module
  directly.
  """
  use Ecto.Repo,
    otp_app: :crisis_map,
    adapter: Ecto.Adapters.Postgres
end
