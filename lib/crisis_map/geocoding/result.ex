defmodule CrisisMap.Geocoding.Result do
  @moduledoc """
  What a geocoder answers with, independent of which geocoder answered.

  `candidates` is the number of places the geocoder considered plausible and
  `confidence` is its own ranking score for the one we took. Both are stored
  on the event, so an ambiguous location stays visibly ambiguous instead of
  looking like a certainty.
  """

  @enforce_keys [:lat, :lon]
  defstruct [:lat, :lon, :display_name, :confidence, candidates: 1]

  @type t :: %__MODULE__{
          lat: float(),
          lon: float(),
          display_name: String.t() | nil,
          confidence: float() | nil,
          candidates: non_neg_integer()
        }
end
