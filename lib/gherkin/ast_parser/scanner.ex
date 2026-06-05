defmodule Gherkin.AstParser.Scanner do
  @moduledoc """
  Turns raw `.feature` text into one `Gherkin.AstParser.Token` per line, classified
  against a `Gherkin.Dialect` keyword set.

  The scanner is deliberately *context-light*: it classifies each line in isolation
  against the active dialect, exactly like the reference `GherkinLine` + token-matcher
  split. The parser supplies the surrounding grammar (e.g. that a `\"""`-delimited
  block's body lines are verbatim `:other`, not re-scanned) by switching the scanner
  into a doc-string mode while consuming a fence.

  Responsibilities:

    * strip a trailing `\\r` (CRLF inputs) from each line,
    * compute 1-indexed `line` and the `column` of the first non-space character,
    * honour a leading `# language: xx` header to pick the dialect,
    * classify the trimmed line into a token type + payload.

  Doc-string bodies are *not* classified here line-by-line by the parser walk; the
  parser asks the scanner only for the line stream and handles fenced regions itself,
  so significant indentation inside a doc string is preserved byte-for-byte.
  """

  alias Gherkin.Dialect
  alias Gherkin.AstParser.Token

  @language_re ~r/^\s*#\s*language\s*:\s*(?<lang>[^\s]+)\s*$/

  @doc """
  Scan `data` into `{:ok, tokens, language}` or `{:error, {message, line, column}}`
  when the `# language:` header names an unknown dialect.

  `tokens` is the full line stream (including `:empty` and `:comment` tokens) so the
  parser can collect comments and compute locations.
  """
  @spec scan(String.t()) ::
          {:ok, [Token.t()], String.t()} | {:error, {String.t(), pos_integer(), pos_integer()}}
  def scan(data) do
    raw_lines = split_lines(data)
    {language, lang_error} = detect_language(raw_lines)

    case lang_error do
      nil ->
        tokens =
          raw_lines
          |> Enum.with_index(1)
          |> Enum.map(fn {raw, idx} -> classify(raw, idx, language) end)

        {:ok, tokens, language}

      err ->
        {:error, err}
    end
  end

  # Split into lines, stripping a single trailing \r per line (CRLF support). A
  # trailing newline does NOT create a spurious empty final line.
  defp split_lines(data) do
    data
    |> String.split("\n")
    |> drop_trailing_empty()
    |> Enum.map(&String.replace_suffix(&1, "\r", ""))
  end

  # `"a\nb\n"` -> ["a","b"] not ["a","b",""]. But `"a\nb"` -> ["a","b"], and ""
  # -> [""] (one empty line, matching upstream's single empty token for empty input
  # is actually no tokens; handled by the parser's empty-feature path).
  defp drop_trailing_empty(parts) do
    case Enum.reverse(parts) do
      ["" | rest] -> Enum.reverse(rest)
      _ -> parts
    end
  end

  defp detect_language(lines) do
    case lines do
      [first | _] ->
        case Regex.named_captures(@language_re, first) do
          %{"lang" => lang} ->
            if Dialect.exists?(lang) do
              {lang, nil}
            else
              col = leading_space_count(first) + 1
              {nil, {"Language not supported: #{lang}", 1, col}}
            end

          nil ->
            {"en", nil}
        end

      [] ->
        {"en", nil}
    end
  end

  # --- per-line classification ------------------------------------------------

  defp classify(raw, line, language) do
    trimmed = String.trim_leading(raw)
    indent = leading_space_count(raw)
    column = indent + 1

    cond do
      trimmed == "" ->
        %Token{type: :empty, line: line, column: 1, raw: raw, payload: %{}}

      language_header?(raw) and line == 1 ->
        %Token{type: :language, line: line, column: column, raw: raw, payload: %{}}

      String.starts_with?(trimmed, "#") ->
        %Token{type: :comment, line: line, column: 1, raw: raw, payload: %{}}

      String.starts_with?(trimmed, "@") ->
        tags = parse_tags(raw, line)
        %Token{type: :tag_line, line: line, column: column, raw: raw, payload: %{tags: tags}}

      doc_string_separator(trimmed) != nil ->
        {delim, rest} = doc_string_separator(trimmed)

        %Token{
          type: :doc_string_separator,
          line: line,
          column: column,
          raw: raw,
          payload: %{delimiter: delim, media_type: media_type(rest)}
        }

      String.starts_with?(trimmed, "|") ->
        cells = parse_cells(raw, line)
        %Token{type: :table_row, line: line, column: column, raw: raw, payload: %{cells: cells}}

      true ->
        classify_keyword(raw, trimmed, line, column, language)
    end
  end

  defp language_header?(raw), do: Regex.match?(@language_re, raw)

  # Block keywords (Feature:, Rule:, ...) are "keyword" + optional ":" + name.
  # Step keywords carry their trailing space and have no ":".
  defp classify_keyword(raw, trimmed, line, column, language) do
    block_groups = [
      {:feature_line, :feature},
      {:background_line, :background},
      {:scenario_outline_line, :scenario_outline},
      {:scenario_line, :scenario},
      {:examples_line, :examples},
      {:rule_line, :rule}
    ]

    case match_block(trimmed, block_groups, language) do
      {type, keyword, name} ->
        %Token{
          type: type,
          line: line,
          column: column,
          raw: raw,
          payload: %{keyword: keyword, text: name}
        }

      nil ->
        case match_step(trimmed, language) do
          {keyword, text} ->
            %Token{
              type: :step_line,
              line: line,
              column: column,
              raw: raw,
              payload: %{keyword: keyword, text: text}
            }

          nil ->
            %Token{type: :other, line: line, column: column, raw: raw, payload: %{text: trimmed}}
        end
    end
  end

  # Try block keyword groups in priority order. Scenario Outline must be tried before
  # Scenario so the longer keyword wins. A block keyword is followed by ":".
  defp match_block(_trimmed, [], _language), do: nil

  defp match_block(trimmed, [{type, group} | rest], language) do
    keywords = Dialect.keywords!(language, group)

    case longest_block_match(trimmed, keywords) do
      {keyword, after_colon} -> {type, keyword, after_colon}
      nil -> match_block(trimmed, rest, language)
    end
  end

  defp longest_block_match(trimmed, keywords) do
    keywords
    |> Enum.filter(fn kw -> String.starts_with?(trimmed, kw <> ":") end)
    |> Enum.max_by(&String.length/1, fn -> nil end)
    |> case do
      nil ->
        nil

      keyword ->
        name = trimmed |> String.replace_prefix(keyword <> ":", "") |> String.trim()
        {keyword, name}
    end
  end

  defp match_step(trimmed, language) do
    Dialect.step_keywords!(language)
    |> Enum.filter(fn kw -> String.starts_with?(trimmed, kw) end)
    |> Enum.max_by(&String.length/1, fn -> nil end)
    |> case do
      nil ->
        nil

      keyword ->
        text = String.replace_prefix(trimmed, keyword, "")
        {keyword, String.trim_trailing(text)}
    end
  end

  # --- helpers ----------------------------------------------------------------

  defp leading_space_count(line) do
    line
    |> String.graphemes()
    |> Enum.take_while(&(&1 == " " or &1 == "\t"))
    |> length()
  end

  defp doc_string_separator(trimmed) do
    cond do
      String.starts_with?(trimmed, "\"\"\"") ->
        {"\"\"\"", String.replace_prefix(trimmed, "\"\"\"", "")}

      String.starts_with?(trimmed, "```") ->
        {"```", String.replace_prefix(trimmed, "```", "")}

      true ->
        nil
    end
  end

  defp media_type(rest) do
    case String.trim(rest) do
      "" -> nil
      mt -> mt
    end
  end

  # Tags: split on whitespace; each `@tag` token records the column where it starts.
  # `@a@b` (joined) is a single tag named "@a@b" (matches upstream).
  defp parse_tags(raw, line) do
    indent = leading_space_count(raw)

    raw
    |> tag_spans()
    |> Enum.map(fn {tag, offset} ->
      %{name: tag, line: line, column: indent_aware_column(raw, indent, offset)}
    end)
  end

  # Walk the raw line, recording each non-whitespace run starting with @ along with
  # its 0-based character offset.
  defp tag_spans(raw) do
    graphemes = String.graphemes(raw)
    do_tag_spans(graphemes, 0, [])
  end

  defp do_tag_spans([], _i, acc), do: Enum.reverse(acc)

  defp do_tag_spans([g | rest], i, acc) when g in [" ", "\t"], do: do_tag_spans(rest, i + 1, acc)

  # A whitespace-separated run beginning with `#` starts a trailing comment and ends
  # tag parsing (`@comment_tag1 #a comment` -> one tag).
  defp do_tag_spans(["#" | _rest], _i, acc), do: Enum.reverse(acc)

  # A non-whitespace run is one or more `@`-delimited tags: `@a@b` -> `@a`, `@b`,
  # each at the column of its own `@`. A `#` inside the run (no leading whitespace)
  # stays part of the tag name (`@comment_tag#2`).
  defp do_tag_spans(graphemes, i, acc) do
    {run, remaining} = Enum.split_while(graphemes, &(&1 != " " and &1 != "\t"))
    tags = split_run_into_tags(run, i)
    do_tag_spans(remaining, i + length(run), Enum.reverse(tags) ++ acc)
  end

  # Split a contiguous run on each `@` boundary, tracking the column offset of every
  # `@`. A leading fragment before the first `@` (malformed) is ignored.
  defp split_run_into_tags(run, base_offset) do
    run
    |> Enum.with_index()
    |> Enum.filter(fn {g, _} -> g == "@" end)
    |> Enum.map(fn {_, at_idx} -> at_idx end)
    |> tag_segments(run, base_offset)
  end

  defp tag_segments([], _run, _base), do: []

  defp tag_segments(at_indices, run, base) do
    bounds = at_indices ++ [length(run)]

    at_indices
    |> Enum.with_index()
    |> Enum.map(fn {start, n} ->
      stop = Enum.at(bounds, n + 1)
      name = run |> Enum.slice(start, stop - start) |> Enum.join()
      {name, base + start}
    end)
  end

  defp indent_aware_column(_raw, _indent, offset), do: offset + 1

  # Cells: split on unescaped `|`. The cell value is the trimmed inner text with
  # table escapes resolved (`\\`->`\`, `\|`->`|`, `\n`->newline). The cell column is
  # the column of the first non-space char in the cell.
  defp parse_cells(raw, line) do
    # Drop everything up to and including the first `|`; cells are the segments
    # between bars. The trailing segment after the final `|` is discarded (it is not
    # a cell), which `split_cells` does by only emitting a cell when it *sees* a `|`.
    graphemes = String.graphemes(raw)
    first_bar = Enum.find_index(graphemes, &(&1 == "|"))
    after_first = Enum.drop(graphemes, first_bar + 1)
    start_col = first_bar + 2

    {cells, _} = split_cells(after_first, start_col, [], [], start_col)

    cells
    |> Enum.map(fn {chars, start_col} ->
      {trimmed, value_col} = trim_cell(chars, start_col)
      %{value: unescape_cell(trimmed), line: line, column: value_col}
    end)
  end

  # Walk graphemes after the first `|`, accumulating cell chars until an unescaped `|`.
  # `pos` is the 1-based column of the current grapheme.
  defp split_cells([], _pos, _cur, cells, _cur_start), do: {Enum.reverse(cells), nil}

  defp split_cells(["\\", next | rest], pos, cur, cells, cur_start) do
    # Keep escape sequences intact for later unescaping.
    split_cells(rest, pos + 2, [next, "\\" | cur], cells, cur_start)
  end

  defp split_cells(["|" | rest], pos, cur, cells, cur_start) do
    cell = {Enum.reverse(cur), cur_start}
    split_cells(rest, pos + 1, [], [cell | cells], pos + 1)
  end

  defp split_cells([g | rest], pos, cur, cells, cur_start) do
    split_cells(rest, pos + 1, [g | cur], cells, cur_start)
  end

  # Trim leading/trailing whitespace from the cell chars; track the column of the
  # first non-whitespace character. Cucumber trims Unicode whitespace, so the column
  # of e.g. a NBSP/tab-padded cell points at the first visible glyph.
  defp trim_cell(chars, start_col) do
    {leading, rest} = Enum.split_while(chars, &cell_space?/1)
    col = start_col + length(leading)
    value = rest |> Enum.reverse() |> Enum.drop_while(&cell_space?/1) |> Enum.reverse()
    {value, col}
  end

  # Whitespace recognised for cell trimming: ASCII space/tab plus the common Unicode
  # spaces the reference treats as blank (NBSP among them).
  defp cell_space?(g), do: g in [" ", "\t", " ", " ", " ", "　"]

  # Left-to-right unescape of a single cell's escape sequences: `\\`->`\`, `\|`->`|`,
  # `\n`->newline. A `\` before any other char keeps both verbatim. A single pass
  # avoids the double-processing that chained global replaces would cause (e.g.
  # `\\n` must stay `\n`, not become `\`+newline).
  defp unescape_cell(chars), do: do_unescape(chars, [])

  defp do_unescape([], acc), do: acc |> Enum.reverse() |> Enum.join()
  defp do_unescape(["\\", "n" | rest], acc), do: do_unescape(rest, ["\n" | acc])
  defp do_unescape(["\\", "|" | rest], acc), do: do_unescape(rest, ["|" | acc])
  defp do_unescape(["\\", "\\" | rest], acc), do: do_unescape(rest, ["\\" | acc])
  defp do_unescape(["\\", other | rest], acc), do: do_unescape(rest, [other, "\\" | acc])
  defp do_unescape([g | rest], acc), do: do_unescape(rest, [g | acc])
end
