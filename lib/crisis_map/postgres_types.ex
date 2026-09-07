# Postgrex needs to know about PostGIS' binary wire format before the Repo
# starts, hence a compile-time type module rather than runtime configuration.
Postgrex.Types.define(
  CrisisMap.PostgresTypes,
  [Geo.PostGIS.Extension] ++ Ecto.Adapters.Postgres.extensions(),
  json: Jason
)
