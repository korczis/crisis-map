defmodule CrisisMap.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      # --- provenance: verbatim from the source ---------------------------
      add :external_id, :string, null: false
      add :title, :string, null: false
      add :description, :text
      add :type, :string, null: false
      add :location_text, :string
      add :occurred_at, :utc_datetime, null: false

      # --- provenance: derived by us from the source ----------------------
      # geography, not geometry: distances come out in metres on a spheroid,
      # which is what "events within X km" means. NULL is the only honest
      # representation of "we do not know where this happened".
      add :geom, :"geography(Point,4326)"
      add :geocoding_status, :string, null: false, default: "pending"
      add :geocoded_display_name, :string
      add :geocoding_candidates, :integer
      add :geocoding_confidence, :float
      add :geocoded_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # The idempotency key of the whole ingest pipeline.
    create unique_index(:events, [:external_id])
    create index(:events, [:type])
    create index(:events, [:occurred_at])
    create index(:events, [:geom], using: :gist)
  end
end
