defmodule Gherkin.AstParser.MarkdownScanner do
  @moduledoc """
  Scanner for the **Markdown with Gherkin** (MDG) dialect — the `.feature.md` format
  described in `cucumber/gherkin`'s `MARKDOWN_WITH_GHERKIN.md`.

  Like `Gherkin.AstParser.Scanner`, it turns raw source into one
  `Gherkin.AstParser.Token` per line so the *same* recursive-descent parser
  (`Gherkin.AstParser`) can consume the stream and produce an identical AST/pickles to
  the equivalent classic `.feature`. Only the per-line classification differs; it is a
  port of the reference `GherkinInMarkdownTokenMatcher`.

  ## Markdown classification rules

    * **Headers** — a line `\#{1,6} <keyword>: <name>` is the matching block line
      (`# Feature:`, `## Rule:`, `## Background:`, `### Scenario:` /
      `### Scenario Outline:`, `#### Examples:`). The token column is
      `indent + len("### ") + 1`.
    * **First-line Feature fallback** — the `# Feature:` header is optional. The first
      significant line (after leading blanks / tag lines) that is not already a
      recognised block becomes the `Feature` line, with the whole trimmed line as its
      name. This mirrors the reference `match_FeatureLine` fallback.
    * **Steps** — a Markdown list item `[*+-] <step keyword> <text>` is a step. The
      `* ` star keyword is *not* a step keyword here; the bullet marker plays its role.
    * **Tables** — GFM table rows indented **2-5 spaces** are data/examples table rows.
      Unindented GFM tables are ignored (neutered to `:empty`).
    * **GFM separator rows** (`| --- |`, `| :-- |`, …) — a row whose cells are all
      `:?-+:?` is *not* a data-table row. The reference `match_Comment` matches it
      (regardless of indent) as a `#Comment`, which — crucially — *opens* a
      `Description` rule when one is expected. We therefore classify it as `:comment`
      (not `:empty`). It contributes no text, but, like the reference, it lets the
      following `#Other` / blank lines be collected as description text. This is why
      the leading `| boz | boo |`-style table in the CCK `markdown` sample becomes the
      `feature.description`.
    * **Doc Strings** — GFM fenced code blocks (``` ``` ```/longer) are doc-string
      separators; the body between fences is verbatim `:other`.
    * **Tags** — backtick-wrapped `` `@tag` `` items on a line above a keyword.
    * **Everything else** ("neutered") — any line that matches no Gherkin token,
      including prose and non-keyword `#` headers, becomes `:empty`. Most MDG documents
      therefore have empty descriptions, exactly like the reference; a description is
      populated only when a GFM-separator `:comment` (or an in-description `:other`)
      opens one.

  Per the reference, MDG does not support `# language:` headers; the dialect is fixed
  to the default (`en`) for the whole document.
  """

  alias Gherkin.AstParser.Scanner
  alias Gherkin.AstParser.Token
  alias Gherkin.Dialect

  @header_re ~r/^(\#{1,6}\s)(.*)$/
  # 1-5 leading whitespace then `|` (reference: /^\s\s\s?\s?\s?\|/ is 2-5; the leading
  # cell column maths uses the actual indent). We accept 2-5 spaces to match the spec.
  @table_re ~r/^\s{2,5}\|/
  # A fenced code block opener/closer: 3+ backticks, capturing the fence and rest.
  @fence_re ~r/^(```+)(.*)$/
  @tag_re ~r/`(@[^`]+)`/

  @doc """
  Scan MDG `data` into `{:ok, [Token.t()], language}`.

  The language is always the default `"en"` (MDG has no inline language header). The
  return shape matches `Gherkin.AstParser.Scanner.scan/1` so the parser is agnostic to
  which scanner produced the stream.
  """
  @spec scan(String.t()) :: {:ok, [Token.t()], String.t()}
  def scan(data) do
    language = "en"

    {tokens, _state} =
      data
      |> split_lines()
      |> Enum.with_index(1)
      |> Enum.map_reduce(%{feature_matched?: false, fence: nil}, fn {raw, idx}, state ->
        classify(raw, idx, language, state)
      end)

    {:ok, tokens, language}
  end

  # Reuse the classic scanner's line splitting (CRLF handling, no spurious trailing
  # empty line). It is a pure transform on the raw text.
  defp split_lines(data) do
    data
    |> String.split("\n")
    |> drop_trailing_empty()
    |> Enum.map(&String.replace_suffix(&1, "\r", ""))
  end

  defp drop_trailing_empty(parts) do
    case Enum.reverse(parts) do
      ["" | rest] -> Enum.reverse(rest)
      _ -> parts
    end
  end

  # --- per-line classification (stateful: doc-string fence + feature-seen) -----

  # Inside an open doc string, only the matching closing fence ends it; every other
  # line is verbatim `:other` body (no re-classification).
  defp classify(raw, line, _language, %{fence: fence} = state) when fence != nil do
    trimmed = String.trim_leading(raw)

    case Regex.run(@fence_re, trimmed) do
      [_, ^fence, _rest] ->
        {sep_token(raw, line, fence, ""), %{state | fence: nil}}

      _ ->
        {%Token{type: :other, line: line, column: 1, raw: raw, payload: %{text: raw}}, state}
    end
  end

  defp classify(raw, line, language, state) do
    trimmed = String.trim_leading(raw)
    indent = leading_space_count(raw)

    cond do
      trimmed == "" ->
        {empty(raw, line), state}

      (tags = tag_items(raw, line)) != [] ->
        {%Token{
           type: :tag_line,
           line: line,
           column: indent + 1,
           raw: raw,
           payload: %{tags: tags, markdown: true}
         }, state}

      (fence = fence_open(trimmed)) != nil ->
        {delim, rest} = fence
        {sep_token(raw, line, delim, media_type(rest)), %{state | fence: delim}}

      (block = header_block(trimmed, indent, raw, line, language)) != nil ->
        {block, %{state | feature_matched?: true}}

      (step = bullet_step(trimmed, indent, raw, line, language)) != nil ->
        {step, state}

      (row = table_row(raw, line)) != nil ->
        {row, state}

      (comment = gfm_separator_comment(trimmed, raw, line)) != nil ->
        {comment, state}

      not state.feature_matched? ->
        # First significant, non-block line becomes the Feature line (whole-line name).
        {%Token{
           type: :feature_line,
           line: line,
           column: indent + 1,
           raw: raw,
           payload: %{keyword: nil, text: trimmed}
         }, %{state | feature_matched?: true}}

      true ->
        # Neutered: any other line (prose, GFM separators, non-keyword headers).
        {empty(raw, line), state}
    end
  end

  defp empty(raw, line),
    do: %Token{type: :empty, line: line, column: 1, raw: raw, payload: %{}}

  defp sep_token(raw, line, delim, media_type) do
    %Token{
      type: :doc_string_separator,
      line: line,
      column: leading_space_count(raw) + 1,
      raw: raw,
      payload: %{delimiter: delim, media_type: blank_to_nil(media_type)}
    }
  end

  # --- headers (block keyword lines) ------------------------------------------

  # Block keyword groups, longest keyword first within a group, Scenario Outline tried
  # before Scenario so the longer keyword wins.
  @block_groups [
    {:feature_line, :feature},
    {:background_line, :background},
    {:rule_line, :rule},
    {:scenario_outline_line, :scenario_outline},
    {:scenario_line, :scenario},
    {:examples_line, :examples}
  ]

  defp header_block(trimmed, indent, raw, line, language) do
    case Regex.run(@header_re, trimmed) do
      [_, prefix, after_prefix] ->
        match_block_keyword(after_prefix, @block_groups, language)
        |> case do
          {type, keyword, name} ->
            %Token{
              type: type,
              line: line,
              # column = indent + length of the "### " prefix + 1
              column: indent + String.length(prefix) + 1,
              raw: raw,
              payload: %{keyword: keyword, text: name}
            }

          nil ->
            nil
        end

      _ ->
        nil
    end
  end

  defp match_block_keyword(_after_prefix, [], _language), do: nil

  defp match_block_keyword(after_prefix, [{type, group} | rest], language) do
    keywords = Dialect.keywords!(language, group)

    keywords
    |> Enum.filter(fn kw -> String.starts_with?(after_prefix, kw <> ":") end)
    |> Enum.max_by(&String.length/1, fn -> nil end)
    |> case do
      nil ->
        match_block_keyword(after_prefix, rest, language)

      keyword ->
        name = after_prefix |> String.replace_prefix(keyword <> ":", "") |> String.trim()
        {type, keyword, name}
    end
  end

  # --- steps (bullet list items) ----------------------------------------------

  @bullet_re ~r/^([*+-]\s+)(.*)$/

  defp bullet_step(trimmed, indent, raw, line, language) do
    case Regex.run(@bullet_re, trimmed) do
      [_, bullet, after_bullet] ->
        # `* ` is the bullet marker here, never a step keyword.
        keywords = Dialect.step_keywords!(language) |> Enum.reject(&(&1 == "* "))

        keywords
        |> Enum.filter(fn kw -> String.starts_with?(after_bullet, kw) end)
        |> Enum.max_by(&String.length/1, fn -> nil end)
        |> case do
          nil ->
            nil

          keyword ->
            text = after_bullet |> String.replace_prefix(keyword, "") |> String.trim()

            %Token{
              type: :step_line,
              line: line,
              column: indent + String.length(bullet) + 1,
              raw: raw,
              payload: %{keyword: keyword, text: text}
            }
        end

      _ ->
        nil
    end
  end

  # --- tables -----------------------------------------------------------------

  defp table_row(raw, line) do
    if Regex.match?(@table_re, raw) do
      cells = Scanner.parse_cells(raw, line)

      if gfm_separator?(cells) do
        nil
      else
        %Token{
          type: :table_row,
          line: line,
          column: leading_space_count(raw) + 1,
          raw: raw,
          payload: %{cells: cells}
        }
      end
    else
      nil
    end
  end

  # A GFM table separator row has at least one cell matching `:?-+:?` (e.g. `---`,
  # `:--`, `--:`). Such rows are not Gherkin table rows.
  defp gfm_separator?(cells) do
    Enum.any?(cells, fn %{value: v} -> Regex.match?(~r/^:?-+:?$/, v) end)
  end

  # Reference `match_Comment`: a line that (trimmed) starts with `|` and whose cells
  # form a GFM separator row matches as a `#Comment` — at *any* indent (an indented
  # separator inside a table is handled here too, since `table_row/2` returns nil for
  # separators). A `#Comment` carries no text but *opens* a description when one is
  # expected (see `Gherkin.AstParser.take_description_lines/4`). Non-separator `|`
  # lines do NOT match here and fall through to be neutered to `:empty`.
  defp gfm_separator_comment(trimmed, raw, line) do
    if String.starts_with?(trimmed, "|") and gfm_separator?(Scanner.parse_cells(raw, line)) do
      # `gfm_separator: true` marks this as a *match_Comment* token that opens a
      # description but is NOT a real document comment (the reference sets its
      # matchedType to Empty, so it never appears in `gherkinDocument.comments`).
      %Token{
        type: :comment,
        line: line,
        column: leading_space_count(raw) + 1,
        raw: raw,
        payload: %{gfm_separator: true}
      }
    else
      nil
    end
  end

  # --- tags (backtick-wrapped) ------------------------------------------------

  # Collect each `` `@tag` `` occurrence; the tag column is the column of the `@`
  # (one past the opening backtick). Returns [] when the line has no backtick tag.
  defp tag_items(raw, line) do
    trimmed = String.trim_leading(raw)
    indent = leading_space_count(raw)

    Regex.scan(@tag_re, trimmed, return: :index)
    |> Enum.map(fn [{_full_start, _full_len}, {name_start, name_len}] ->
      name = binary_part(trimmed, name_start, name_len)
      %{name: name, line: line, column: indent + name_start + 1}
    end)
  end

  # --- helpers ----------------------------------------------------------------

  defp fence_open(trimmed) do
    case Regex.run(@fence_re, trimmed) do
      [_, fence, rest] -> {fence, rest}
      _ -> nil
    end
  end

  defp media_type(rest), do: String.trim(rest)
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s), do: s

  defp leading_space_count(line) do
    line
    |> String.graphemes()
    |> Enum.take_while(&(&1 == " " or &1 == "\t"))
    |> length()
  end
end
