defmodule Gherkin.AST do
  @moduledoc """
  The reference-pipeline AST: faithful structs for a parsed `.feature` document.

  These structs are the target output of the (not-yet-built) scanner+parser, and
  the input to the (not-yet-built) pickles compiler. Their field names and nesting
  mirror the official cucumber-messages `GherkinDocument` schema so that the NDJSON
  serializer (`Gherkin.Message`) is a near-mechanical projection.

  This is intentionally separate from the legacy `Gherkin.Elements.*` structs, which
  the current public `Gherkin.parse/1` API and its tests still depend on. The legacy
  structs stay until the new parser fully replaces them.

  ## Node map (cucumber-messages name -> module)

      GherkinDocument -> Gherkin.AST.GherkinDocument
      Feature         -> Gherkin.AST.Feature
      Rule            -> Gherkin.AST.Rule
      Background      -> Gherkin.AST.Background
      Scenario        -> Gherkin.AST.Scenario   (also represents Scenario Outline)
      Examples        -> Gherkin.AST.Examples
      Step            -> Gherkin.AST.Step
      DataTable       -> Gherkin.AST.DataTable
      TableRow        -> Gherkin.AST.TableRow
      TableCell       -> Gherkin.AST.TableCell
      DocString       -> Gherkin.AST.DocString
      Tag             -> Gherkin.AST.Tag
      Comment         -> Gherkin.AST.Comment

  A Feature/Rule `children` list holds tagged tuples in source order so background,
  rules and scenarios keep their relative position, matching the messages schema's
  `FeatureChild` / `RuleChild` union:

      {:background, %Background{}} | {:rule, %Rule{}} | {:scenario, %Scenario{}}
  """

  defmodule GherkinDocument do
    @moduledoc "Top-level parsed document. `uri`, optional `feature`, and all `comments`."
    @type t :: %__MODULE__{
            uri: String.t() | nil,
            feature: Gherkin.AST.Feature.t() | nil,
            comments: [Gherkin.AST.Comment.t()]
          }
    defstruct uri: nil, feature: nil, comments: []
  end

  defmodule Feature do
    @moduledoc "A Feature node. `children` is an ordered list of `{:background|:rule|:scenario, node}`."
    @type child ::
            {:background, Gherkin.AST.Background.t()}
            | {:rule, Gherkin.AST.Rule.t()}
            | {:scenario, Gherkin.AST.Scenario.t()}
    @type t :: %__MODULE__{
            location: Gherkin.Location.t(),
            language: String.t(),
            keyword: String.t(),
            name: String.t(),
            description: String.t(),
            tags: [Gherkin.AST.Tag.t()],
            children: [child()]
          }
    defstruct location: nil,
              language: "en",
              keyword: "Feature",
              name: "",
              description: "",
              tags: [],
              children: []
  end

  defmodule Rule do
    @moduledoc "A Rule node (Gherkin 6). `children` is `{:background|:scenario, node}`."
    @type child ::
            {:background, Gherkin.AST.Background.t()}
            | {:scenario, Gherkin.AST.Scenario.t()}
    @type t :: %__MODULE__{
            id: String.t() | nil,
            location: Gherkin.Location.t(),
            keyword: String.t(),
            name: String.t(),
            description: String.t(),
            tags: [Gherkin.AST.Tag.t()],
            children: [child()]
          }
    defstruct id: nil,
              location: nil,
              keyword: "Rule",
              name: "",
              description: "",
              tags: [],
              children: []
  end

  defmodule Background do
    @moduledoc "A Background node. Its steps are prepended to every sibling scenario's pickle."
    @type t :: %__MODULE__{
            id: String.t() | nil,
            location: Gherkin.Location.t(),
            keyword: String.t(),
            name: String.t(),
            description: String.t(),
            steps: [Gherkin.AST.Step.t()]
          }
    defstruct id: nil,
              location: nil,
              keyword: "Background",
              name: "",
              description: "",
              steps: []
  end

  defmodule Scenario do
    @moduledoc """
    A Scenario node. Also represents a Scenario Outline / Template: when `examples`
    is non-empty the pickles compiler expands one pickle per example row.
    """
    @type t :: %__MODULE__{
            id: String.t() | nil,
            location: Gherkin.Location.t(),
            keyword: String.t(),
            name: String.t(),
            description: String.t(),
            tags: [Gherkin.AST.Tag.t()],
            steps: [Gherkin.AST.Step.t()],
            examples: [Gherkin.AST.Examples.t()]
          }
    defstruct id: nil,
              location: nil,
              keyword: "Scenario",
              name: "",
              description: "",
              tags: [],
              steps: [],
              examples: []
  end

  defmodule Examples do
    @moduledoc "An Examples table under a Scenario Outline. `table_header` + `table_body` rows."
    @type t :: %__MODULE__{
            id: String.t() | nil,
            location: Gherkin.Location.t(),
            keyword: String.t(),
            name: String.t(),
            description: String.t(),
            tags: [Gherkin.AST.Tag.t()],
            table_header: Gherkin.AST.TableRow.t() | nil,
            table_body: [Gherkin.AST.TableRow.t()]
          }
    defstruct id: nil,
              location: nil,
              keyword: "Examples",
              name: "",
              description: "",
              tags: [],
              table_header: nil,
              table_body: []
  end

  defmodule Step do
    @moduledoc """
    A single step. `keyword` keeps its trailing space (e.g. `"Given "`) to match the
    reference output. `keyword_type` is one of `Context|Action|Outcome|Conjunction|Unknown`.
    Exactly one of `data_table` / `doc_string` may be present (or neither).
    """
    @type keyword_type :: String.t()
    @type t :: %__MODULE__{
            id: String.t() | nil,
            location: Gherkin.Location.t(),
            keyword: String.t(),
            keyword_type: keyword_type() | nil,
            text: String.t(),
            data_table: Gherkin.AST.DataTable.t() | nil,
            doc_string: Gherkin.AST.DocString.t() | nil
          }
    defstruct id: nil,
              location: nil,
              keyword: "",
              keyword_type: nil,
              text: "",
              data_table: nil,
              doc_string: nil
  end

  defmodule DataTable do
    @moduledoc "A `|`-delimited data table attached to a step."
    @type t :: %__MODULE__{
            location: Gherkin.Location.t(),
            rows: [Gherkin.AST.TableRow.t()]
          }
    defstruct location: nil, rows: []
  end

  defmodule TableRow do
    @moduledoc "A single row of a data table or examples table."
    @type t :: %__MODULE__{
            id: String.t() | nil,
            location: Gherkin.Location.t(),
            cells: [Gherkin.AST.TableCell.t()]
          }
    defstruct id: nil, location: nil, cells: []
  end

  defmodule TableCell do
    @moduledoc "A single cell. `value` is always a string (no atom keys)."
    @type t :: %__MODULE__{
            location: Gherkin.Location.t(),
            value: String.t()
          }
    defstruct location: nil, value: ""
  end

  defmodule DocString do
    @moduledoc """
    A doc string attached to a step. `delimiter` is `\"\"\"` or a backtick fence.
    `media_type` is the optional content-type after the opening fence (nil if absent).
    """
    @type t :: %__MODULE__{
            location: Gherkin.Location.t(),
            media_type: String.t() | nil,
            content: String.t(),
            delimiter: String.t()
          }
    defstruct location: nil, media_type: nil, content: "", delimiter: "\"\"\""
  end

  defmodule Tag do
    @moduledoc "A `@tag`. `name` includes the leading `@`. Has an `id` and a `location`."
    @type t :: %__MODULE__{
            id: String.t() | nil,
            location: Gherkin.Location.t(),
            name: String.t()
          }
    defstruct id: nil, location: nil, name: ""
  end

  defmodule Comment do
    @moduledoc "A `#` comment line, preserved verbatim (including leading whitespace)."
    @type t :: %__MODULE__{
            location: Gherkin.Location.t(),
            text: String.t()
          }
    defstruct location: nil, text: ""
  end
end
