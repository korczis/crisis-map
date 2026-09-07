defmodule CrisisMap.Ingest.Source do
  @moduledoc """
  Where raw records come from.

  Only one source shape exists today (a JSON array in a file) and that is on
  purpose: the exercise asks for one vertical path, not a crawler framework.
  It is a separate module so that a second source becomes a new function here
  rather than a change to the importer.
  """

  @default_path "priv/data/events.json"

  @doc "The dataset shipped with the application."
  @spec default_path() :: String.t()
  def default_path, do: Application.app_dir(:crisis_map, @default_path)

  @doc "The dataset path as written in the repository, for messages and docs."
  @spec default_path_relative() :: String.t()
  def default_path_relative, do: @default_path

  @doc "Reads a JSON array of records from disk."
  @spec read_json(String.t()) :: {:ok, [map()]} | {:error, term()}
  def read_json(path) do
    with {:ok, body} <- File.read(path),
         {:ok, decoded} <- Jason.decode(body) do
      case decoded do
        records when is_list(records) -> {:ok, records}
        _ -> {:error, {:not_a_list, path}}
      end
    end
  end
end
