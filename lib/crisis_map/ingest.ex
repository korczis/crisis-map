defmodule CrisisMap.Ingest do
  @moduledoc """
  The ingest pipeline: raw records in, stored events out.

      raw record -> normalise -> persist (idempotent) -> geocode -> persist position

  Two properties matter more than anything else here.

  **Idempotency.** Identity is the source's `external_id`, which carries a
  unique index. Importing the same file twice produces the same number of
  rows; the second run updates them in place.

  **Isolation.** Every record is processed on its own. A record that fails to
  normalise, a place the geocoder does not know and a geocoder that is down
  are three different outcomes, all of them counted in the report, none of
  them able to abort the run.
  """

  require Logger

  alias CrisisMap.Events
  alias CrisisMap.Events.Event
  alias CrisisMap.Geocoding
  alias CrisisMap.Geocoding.Result
  alias CrisisMap.Ingest.Normalizer
  alias CrisisMap.Ingest.Source

  @type report :: %{
          total: non_neg_integer(),
          inserted: non_neg_integer(),
          updated: non_neg_integer(),
          invalid: non_neg_integer(),
          geocoded: non_neg_integer(),
          not_found: non_neg_integer(),
          geocoder_errors: non_neg_integer(),
          reused: non_neg_integer(),
          skipped: non_neg_integer(),
          errors: [map()]
        }

  @empty_report %{
    total: 0,
    inserted: 0,
    updated: 0,
    invalid: 0,
    geocoded: 0,
    not_found: 0,
    geocoder_errors: 0,
    reused: 0,
    skipped: 0,
    errors: []
  }

  @doc """
  Imports the dataset from a JSON file (the bundled one by default).

  Options:

    * `:path` — dataset to read;
    * `:regeocode` — `true` re-resolves positions that are already known.
  """
  @spec import_file(keyword()) :: {:ok, report()} | {:error, term()}
  def import_file(opts \\ []) do
    path = Keyword.get(opts, :path) || Source.default_path()

    case Source.read_json(path) do
      {:ok, records} -> {:ok, import_records(records, opts)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Imports a list of raw records."
  @spec import_records([map()], keyword()) :: report()
  def import_records(records, opts \\ []) when is_list(records) do
    records
    |> Enum.reduce(@empty_report, &import_one(&1, &2, opts))
    |> Map.update!(:errors, &Enum.reverse/1)
  end

  defp import_one(raw, report, opts) do
    report = Map.update!(report, :total, &(&1 + 1))

    case Normalizer.normalize(raw) do
      {:ok, attrs} -> persist(attrs, report, opts)
      {:error, reason} -> record_error(report, :invalid, raw, reason)
    end
  rescue
    # Nothing should reach this, which is exactly why it is here: an unforeseen
    # failure costs one record, not the import.
    exception ->
      Logger.error("ingest: record crashed: #{Exception.message(exception)}")
      record_error(report, :invalid, raw, {:exception, Exception.message(exception)})
  end

  defp persist(attrs, report, opts) do
    case Events.upsert_from_source(attrs) do
      {:ok, {outcome, event}} ->
        report
        |> Map.update!(outcome_key(outcome), &(&1 + 1))
        |> locate(event, opts)

      {:error, changeset} ->
        record_error(report, :invalid, attrs, changeset_errors(changeset))
    end
  end

  defp outcome_key(:inserted), do: :inserted
  defp outcome_key(:updated), do: :updated

  # --- localisation ------------------------------------------------------

  defp locate(report, %Event{location_text: nil} = event, _opts) do
    # No place name in the source: not a failure, just nothing to resolve.
    write_geocoding(report, event, :skipped, %{geocoding_status: "skipped", geom: nil})
  end

  defp locate(report, %Event{} = event, opts) do
    if reuse?(event, opts) do
      Map.update!(report, :reused, &(&1 + 1))
    else
      event.location_text
      |> Geocoding.geocode()
      |> apply_geocoding(report, event)
    end
  end

  # A position we already resolved for the same place name is not resolved
  # again: it keeps re-imports cheap and does not hammer the geocoder.
  defp reuse?(%Event{geocoding_status: "ok", geom: %Geo.Point{}}, opts),
    do: not Keyword.get(opts, :regeocode, false)

  defp reuse?(_event, _opts), do: false

  defp apply_geocoding({:ok, %Result{} = result}, report, event) do
    write_geocoding(report, event, :geocoded, %{
      geom: %Geo.Point{coordinates: {result.lon, result.lat}, srid: 4326},
      geocoding_status: "ok",
      geocoded_display_name: result.display_name,
      geocoding_candidates: result.candidates,
      geocoding_confidence: result.confidence
    })
  end

  defp apply_geocoding({:error, :not_found}, report, event) do
    # The geocoder answered and knows no such place. The location text stays,
    # the position stays unknown, and nothing is invented.
    write_geocoding(report, event, :not_found, %{
      geom: nil,
      geocoding_status: "not_found",
      geocoded_display_name: nil,
      geocoding_candidates: 0,
      geocoding_confidence: nil
    })
  end

  defp apply_geocoding({:error, reason}, report, event) do
    Logger.warning(
      "ingest: geocoder failed for #{inspect(event.location_text)}: #{inspect(reason)}"
    )

    report
    |> write_geocoding(event, :geocoder_errors, %{
      geom: nil,
      geocoding_status: "error",
      geocoded_display_name: nil,
      geocoding_candidates: nil,
      geocoding_confidence: nil
    })
    |> add_error(event.external_id, {:geocoder, reason})
  end

  defp write_geocoding(report, event, counter, attrs) do
    case Events.put_geocoding(event, attrs) do
      {:ok, _event} ->
        Map.update!(report, counter, &(&1 + 1))

      {:error, changeset} ->
        add_error(report, event.external_id, changeset_errors(changeset))
    end
  end

  # --- reporting ---------------------------------------------------------

  defp record_error(report, counter, subject, reason) do
    report
    |> Map.update!(counter, &(&1 + 1))
    |> add_error(identify(subject), reason)
  end

  defp add_error(report, subject, reason) do
    Map.update!(report, :errors, &[%{subject: subject, reason: inspect(reason)} | &1])
  end

  defp identify(%{external_id: id}), do: id
  defp identify(%{"external_id" => id}), do: id
  defp identify(_), do: "(unidentified record)"

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end
