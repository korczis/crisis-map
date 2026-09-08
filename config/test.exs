import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :crisis_map, CrisisMap.Repo,
  username: System.get_env("GEO_DB_USER", "academy"),
  password: System.get_env("GEO_DB_PASSWORD", "academy_local_dev_only"),
  hostname: System.get_env("GEO_DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("GEO_DB_PORT", "55432")),
  database: "crisis_map_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :crisis_map, CrisisMapWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "reghgg6WOHgrhZHjZDkA7SBRY/ztDVkduzEVk551SDS0OAm8qDtp5gBLzx7c8SAM",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Tests never reach the network: the fake is driven per-test.
config :crisis_map, :geocoder, CrisisMap.Geocoding.Fake
