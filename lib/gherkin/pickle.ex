defmodule Gherkin.Pickle do
  @moduledoc """
  A `Pickle` is one concrete, runnable scenario — the seam between the parser and a
  runner. By the time a pickle exists, the AST has been fully resolved:

    * scenario-outline rows are expanded (one pickle per Examples row),
    * background steps are prepended,
    * tags are inherited and unioned (Feature -> Rule -> Scenario/Outline -> Examples),
    * `<placeholder>` substitution has been applied (incl. in tables/doc strings).

  Field names mirror the cucumber-messages `Pickle` schema. `ast_node_ids` link a
  pickle back to the AST node(s) it was compiled from. `location` is the source
  location the pickle derives from (the scenario's location, or — for an outline —
  the Examples body-row's location). The runner consumes pickles only — it must
  never re-parse `.feature` syntax.
  """

  @type t :: %__MODULE__{
          id: String.t() | nil,
          uri: String.t() | nil,
          name: String.t(),
          language: String.t(),
          location: Gherkin.Location.t() | nil,
          steps: [Gherkin.PickleStep.t()],
          tags: [Gherkin.Pickle.Tag.t()],
          ast_node_ids: [String.t()]
        }

  defstruct id: nil,
            uri: nil,
            name: "",
            language: "en",
            location: nil,
            steps: [],
            tags: [],
            ast_node_ids: []

  defmodule Tag do
    @moduledoc "A tag on a pickle. `name` includes the leading `@`; links to its source AST tag."
    @type t :: %__MODULE__{name: String.t(), ast_node_id: String.t() | nil}
    defstruct name: "", ast_node_id: nil
  end
end
