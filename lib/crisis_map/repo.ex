defmodule CrisisMap.Repo do
  use Ecto.Repo,
    otp_app: :crisis_map,
    adapter: Ecto.Adapters.Postgres
end
