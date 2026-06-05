defmodule Gherkin.PickleStep do
  @moduledoc """
  A single step inside a `Gherkin.Pickle`, after placeholder substitution.

  `type` is the resolved step type (`Context|Action|Outcome|Unknown`) — note that a
  pickle step never carries the `Conjunction` type: `And`/`But`/`*` are resolved to
  the type of the preceding non-conjunction step during compilation.

  An optional `argument` carries a data table or doc string, mirroring the
  cucumber-messages `PickleStepArgument` union:

      {:data_table, %Gherkin.Pickle.DataTable{}} | {:doc_string, %Gherkin.Pickle.DocString{}} | nil
  """

  @type argument ::
          {:data_table, Gherkin.Pickle.DataTable.t()}
          | {:doc_string, Gherkin.Pickle.DocString.t()}
          | nil

  @type t :: %__MODULE__{
          id: String.t() | nil,
          text: String.t(),
          type: String.t() | nil,
          argument: argument(),
          ast_node_ids: [String.t()]
        }

  defstruct id: nil, text: "", type: nil, argument: nil, ast_node_ids: []
end

defmodule Gherkin.Pickle.DataTable do
  @moduledoc "A data table argument on a pickle step (cells already substituted)."
  @type row :: [String.t()]
  @type t :: %__MODULE__{rows: [row()]}
  defstruct rows: []
end

defmodule Gherkin.Pickle.DocString do
  @moduledoc "A doc string argument on a pickle step (content already substituted)."
  @type t :: %__MODULE__{media_type: String.t() | nil, content: String.t()}
  defstruct media_type: nil, content: ""
end
