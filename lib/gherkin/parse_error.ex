defmodule Gherkin.ParseError do
  @moduledoc """
  Raised by `Gherkin.parse!/2` and `Gherkin.pickles/2` when a `.feature` document
  is malformed.

  `errors` is the list of `{message, %Gherkin.Location{}}` tuples the parser
  produced (in source order); `uri` is the source uri, if one was given.
  """

  defexception [:errors, :uri]

  @type t :: %__MODULE__{
          errors: [{String.t(), Gherkin.Location.t()}],
          uri: String.t() | nil
        }

  @impl true
  def message(%__MODULE__{errors: errors, uri: uri}) do
    where = if uri in [nil, ""], do: "feature", else: uri
    lines = Enum.map_join(errors, "\n", fn {msg, _loc} -> "  " <> msg end)
    "failed to parse #{where}:\n" <> lines
  end
end
