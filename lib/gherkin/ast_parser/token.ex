defmodule Gherkin.AstParser.Token do
  @moduledoc """
  A single scanned line, classified against a dialect's keyword sets.

  One token per source line. The scanner (`Gherkin.AstParser.Scanner`) produces these;
  the parser (`Gherkin.Parser`) consumes them. Every token carries its 1-indexed
  `line` and the 1-indexed `column` of its first significant character.

  ## Token `type`

    * `:empty`            — blank / whitespace-only line
    * `:comment`          — `#` comment line
    * `:language`         — `# language: xx` header (only meaningful as the first line)
    * `:tag_line`         — a line of `@tags`
    * `:feature_line`     — `Feature:` (or dialect synonym)
    * `:rule_line`        — `Rule:`
    * `:background_line`  — `Background:`
    * `:scenario_line`    — `Scenario:` / `Example:`
    * `:scenario_outline_line` — `Scenario Outline:` / `Scenario Template:`
    * `:examples_line`    — `Examples:` / `Scenarios:`
    * `:step_line`        — a Given/When/Then/And/But/`*` step
    * `:doc_string_separator` — `\"\"\"` or ` ``` ` fence
    * `:table_row`        — a `|`-delimited row
    * `:other`            — anything else (description text, doc-string body)
  """

  @type type ::
          :empty
          | :comment
          | :language
          | :tag_line
          | :feature_line
          | :rule_line
          | :background_line
          | :scenario_line
          | :scenario_outline_line
          | :examples_line
          | :step_line
          | :doc_string_separator
          | :table_row
          | :other

  @type t :: %__MODULE__{
          type: type(),
          line: pos_integer(),
          column: pos_integer(),
          # The raw line text with the trailing \r (if any) stripped.
          raw: String.t(),
          # Token-type-specific payload (keyword, text, cells, etc.).
          payload: map()
        }

  defstruct type: :other, line: 0, column: 1, raw: "", payload: %{}
end
