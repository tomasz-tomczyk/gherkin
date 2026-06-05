defmodule Gherkin.AstParser do
  @moduledoc """
  Recursive-descent parser: `Gherkin.AstParser.Token` stream -> `Gherkin.AST.GherkinDocument`.

  This is the parser backing the public `Gherkin.parse/2` API. It mirrors the
  cucumber-messages `GherkinDocument` shape so the serializer in `Gherkin.Message`
  is a near-mechanical projection.

  ## Approach

  The official Gherkin parser is a generated table-driven state machine. We instead
  hand-write a recursive-descent grammar over the token stream — easier to read and
  maintain, and it produces an identical AST for the corpus. Doc-string body
  preservation and significant indentation are handled while consuming fences.

  IDs are *not* assigned during the tree walk; a separate post-order pass
  (`Gherkin.AstParser.IdAssigner`) numbers nodes in the exact order the reference
  AstBuilder does (children, then tags, then the node) so emitted ids match goldens.

  ## Errors

  Returns `{:error, [{message, %Gherkin.Location{}}]}` on malformed input, with
  `(line:col)`-prefixed messages following the reference parser where the
  recursive-descent shape allows (unknown language, inconsistent cell count,
  whitespace in tags, unexpected EOF, unexpected token).
  """

  alias Gherkin.AST.{
    Background,
    Comment,
    DataTable,
    DocString,
    Examples,
    Feature,
    GherkinDocument,
    Rule,
    Scenario,
    Step,
    TableCell,
    TableRow,
    Tag
  }

  alias Gherkin.Dialect
  alias Gherkin.Location
  alias Gherkin.AstParser.{IdAssigner, Scanner, Token}

  # --- description terminator sets (see the descriptions section below) -------
  #
  # The token types that END a description in each context (everything else is
  # consumed as description #Other text). These mirror the reference parser's
  # per-state matcher lists. Declared here so they are defined before use.

  @feature_desc_terminators [
    :background_line,
    :tag_line,
    :scenario_line,
    :scenario_outline_line,
    :rule_line
  ]

  # Background description (reference states 5/6): no ExamplesLine terminator.
  @background_desc_terminators [
    :step_line,
    :tag_line,
    :scenario_line,
    :scenario_outline_line,
    :rule_line
  ]

  # Scenario / Scenario Outline description (reference states 10/11): like Background
  # but ExamplesLine also terminates (an outline with no steps can be followed directly
  # by an Examples block).
  @scenario_desc_terminators [
    :step_line,
    :tag_line,
    :examples_line,
    :scenario_line,
    :scenario_outline_line,
    :rule_line
  ]

  @examples_desc_terminators [
    :table_row,
    :tag_line,
    :examples_line,
    :scenario_line,
    :scenario_outline_line,
    :rule_line
  ]

  # The union of every token type that terminates a description in some context. A
  # token of one of these types ends the description only when it is in the *current*
  # context's terminator set; otherwise it is consumed as description text (#Other).
  @all_desc_terminators Enum.uniq(
                          @feature_desc_terminators ++
                            @background_desc_terminators ++
                            @scenario_desc_terminators ++ @examples_desc_terminators
                        )

  @doc """
  Parse feature `data` for `uri` into `{:ok, %GherkinDocument{}}` or
  `{:error, [{message, %Location{}}]}`.
  """
  @spec parse(String.t(), String.t()) ::
          {:ok, GherkinDocument.t()} | {:error, [{String.t(), Location.t()}]}
  def parse(uri, data) do
    case Scanner.scan(data) do
      {:ok, tokens, language} ->
        do_parse(uri, tokens, language)

      {:error, {message, line, column}} ->
        {:error, [{prefixed(message, line, column), Location.new(line, column)}]}
    end
  end

  defp do_parse(uri, tokens, language) do
    comments = collect_comments(tokens)

    case open_doc_string_error(tokens) do
      nil ->
        {feature, parse_errors} = parse_feature(tokens, language)
        doc = %GherkinDocument{uri: uri, feature: feature, comments: comments}
        finalize(doc, parse_errors)

      error ->
        # An unterminated doc string makes the rest of the parse meaningless; the
        # reference emits a single unexpected-EOF error for it.
        {:error, [error]}
    end
  end

  # If a `"""`/``` fence is opened but never closed, the file ends inside a doc string.
  # Report `(lastLine+1:0): unexpected end of file, expected: #DocStringSeparator, #Other`.
  defp open_doc_string_error(tokens) do
    open? =
      Enum.reduce(tokens, nil, fn
        %Token{type: :doc_string_separator, payload: %{delimiter: d}}, nil -> d
        %Token{type: :doc_string_separator, payload: %{delimiter: d}}, open when d == open -> nil
        _t, open -> open
      end)

    case open? do
      nil ->
        nil

      _ ->
        last_line = tokens |> List.last() |> Map.get(:line)
        line = last_line + 1
        msg = "unexpected end of file, expected: #DocStringSeparator, #Other"
        {prefixed(msg, line, 0), %Location{line: line, column: nil}}
    end
  end

  # Combine structural parse errors (recovered token-level errors) with semantic
  # validation errors (e.g. inconsistent table cell counts), sorted into source order
  # by line/column so multi-error output matches the reference ordering.
  defp finalize(doc, parse_errors) do
    errors = parse_errors ++ validate(doc)

    case errors do
      [] ->
        {:ok, IdAssigner.assign(doc)}

      _ ->
        sorted =
          Enum.sort_by(errors, fn {_msg, %Location{line: l, column: c}} -> {l, c || 0} end)

        {:error, sorted}
    end
  end

  # --- comments ---------------------------------------------------------------

  defp collect_comments(tokens) do
    tokens
    |> skip_doc_string_regions()
    |> Enum.filter(&(&1.type == :comment))
    |> Enum.map(fn t ->
      %Comment{location: %Location{line: t.line, column: 1}, text: t.raw}
    end)
  end

  defp skip_doc_string_regions(tokens), do: do_skip(tokens, nil, [])

  defp do_skip([], _open, acc), do: Enum.reverse(acc)

  defp do_skip(
         [%Token{type: :doc_string_separator, payload: %{delimiter: d}} = t | rest],
         nil,
         acc
       ),
       do: do_skip(rest, d, [t | acc])

  defp do_skip(
         [%Token{type: :doc_string_separator, payload: %{delimiter: d}} = t | rest],
         open,
         acc
       )
       when d == open,
       do: do_skip(rest, nil, [t | acc])

  defp do_skip([_t | rest], open, acc) when open != nil, do: do_skip(rest, open, acc)
  defp do_skip([t | rest], nil, acc), do: do_skip(rest, nil, [t | acc])

  # --- feature ----------------------------------------------------------------

  # Returns `{feature_or_nil, errors}`. Junk lines before the Feature header are
  # recorded as errors and skipped (error recovery), matching the reference parser.
  defp parse_feature(tokens, language) do
    {feature_tags, rest} = take_tags(tokens)

    case rest do
      [%Token{type: :feature_line} = ft | after_feature] ->
        {description, body} = take_description(after_feature, @feature_desc_terminators)
        {children, _rest, errors} = parse_children(body, language, [], :feature, [])

        feature = %Feature{
          location: loc(ft),
          language: language,
          keyword: ft.payload.keyword,
          name: ft.payload.text,
          description: description,
          tags: build_tags(feature_tags),
          children: children
        }

        {feature, errors}

      [] ->
        {nil, []}

      [%Token{type: :other} = junk | _] ->
        # Pre-feature junk: record, skip the line, retry from the next line.
        error = unexpected(junk, feature_expected())
        {feature, errors} = parse_feature(drop_line(tokens, junk), language)
        {feature, [error | errors]}

      [other | _] ->
        {nil, [unexpected(other, feature_expected())]}
    end
  end

  # Drop tokens up to and including the token on the given line, so recovery resumes
  # on the following line.
  defp drop_line(tokens, %Token{line: line}) do
    Enum.drop_while(tokens, &(&1.line <= line))
  end

  defp feature_expected do
    ["#EOF", "#Language", "#TagLine", "#FeatureLine", "#Comment", "#Empty"]
  end

  # --- children walk (returns remaining tokens) -------------------------------

  # Returns `{children, remaining_tokens, errors}`. Unrecognized lines are recorded as
  # errors and skipped so multiple errors surface in one pass (error recovery).
  defp parse_children(tokens, language, acc, scope, errors) do
    tokens = skip_noise(tokens)

    case tokens do
      [] ->
        {Enum.reverse(acc), [], Enum.reverse(errors)}

      [%Token{type: :background_line} = bt | rest] ->
        {bg, after_bg} = parse_background(bt, rest, language)
        parse_children(after_bg, language, [{:background, bg} | acc], scope, errors)

      [%Token{type: :rule_line} | _] when scope == :rule ->
        {Enum.reverse(acc), tokens, Enum.reverse(errors)}

      [%Token{type: :rule_line} = rt | rest] when scope == :feature ->
        {rule, after_rule, rerrors} = parse_rule(rt, [], rest, language)

        parse_children(
          after_rule,
          language,
          [{:rule, rule} | acc],
          scope,
          rev_prepend(rerrors, errors)
        )

      [%Token{type: :tag_line} | _] = tagged ->
        {tags, rest} = take_tags(tagged)
        tag_errors = tag_line_errors(tagged)

        case rest do
          [%Token{type: t} = head | hrest] when t in [:scenario_line, :scenario_outline_line] ->
            {scenario, after_sc} = parse_scenario(head, tags, hrest, language)

            parse_children(
              after_sc,
              language,
              [{:scenario, scenario} | acc],
              scope,
              rev_prepend(tag_errors, errors)
            )

          [%Token{type: :rule_line} | _] when scope == :rule ->
            {Enum.reverse(acc), tagged, Enum.reverse(errors)}

          [%Token{type: :rule_line} = rt | rrest] when scope == :feature ->
            {rule, after_rule, rerrors} = parse_rule(rt, tags, rrest, language)

            parse_children(
              after_rule,
              language,
              [{:rule, rule} | acc],
              scope,
              rev_prepend(rerrors, rev_prepend(tag_errors, errors))
            )

          [other | _] ->
            error = unexpected(other, scenario_expected())
            parse_children(drop_line(tokens, other), language, acc, scope, [error | errors])

          [] ->
            error = eof_error(List.last(tagged), tag_eof_expected())
            {Enum.reverse(acc), [], Enum.reverse([error | errors])}
        end

      [%Token{type: t} = head | rest] when t in [:scenario_line, :scenario_outline_line] ->
        {scenario, after_sc} = parse_scenario(head, [], rest, language)
        parse_children(after_sc, language, [{:scenario, scenario} | acc], scope, errors)

      [other | _] ->
        error = unexpected(other, scenario_expected())
        parse_children(drop_line(tokens, other), language, acc, scope, [error | errors])
    end
  end

  defp rev_prepend(new, errors), do: Enum.reverse(new) ++ errors

  # A tag line where a whitespace-separated item does not start with `@` is malformed
  # ("A tag may not contain whitespace"). The reference reports it at the column of
  # the first tag on the line. Returns `[]` when the line is well-formed.
  defp tag_line_errors([%Token{type: :tag_line} = t | _]) do
    raw_items =
      t.raw
      |> String.split(~r/\s+/, trim: true)
      |> Enum.take_while(&(not String.starts_with?(&1, "#")))

    if Enum.all?(raw_items, &String.starts_with?(&1, "@")) do
      []
    else
      msg = "A tag may not contain whitespace"
      loc = %Location{line: t.line, column: t.column}
      [{prefixed(msg, t.line, t.column), loc}]
    end
  end

  defp tag_line_errors(_), do: []

  defp scenario_expected do
    [
      "#EOF",
      "#TableRow",
      "#DocStringSeparator",
      "#StepLine",
      "#TagLine",
      "#ExamplesLine",
      "#ScenarioLine",
      "#RuleLine",
      "#Comment",
      "#Empty"
    ]
  end

  # After a tag line at feature/rule scope, the reference's "expected at EOF" set is
  # this fixed list (a tag may precede a Rule or a Scenario; the state machine reports
  # this exact set when it then hits EOF).
  defp tag_eof_expected, do: ["#TagLine", "#RuleLine", "#Comment", "#Empty"]

  # --- background -------------------------------------------------------------

  defp parse_background(bt, rest, language) do
    {description, after_desc} = take_description(rest, @background_desc_terminators)
    {steps, after_steps} = parse_steps(after_desc, language, [])

    bg = %Background{
      location: loc(bt),
      keyword: bt.payload.keyword,
      name: bt.payload.text,
      description: description,
      steps: steps
    }

    {bg, after_steps}
  end

  # --- rule -------------------------------------------------------------------

  # Returns `{rule, remaining_tokens, errors}`.
  defp parse_rule(rt, tags, rest, language) do
    {description, after_desc} = take_description(rest, @feature_desc_terminators)
    {children, after_children, errors} = parse_children(after_desc, language, [], :rule, [])

    rule = %Rule{
      location: loc(rt),
      keyword: rt.payload.keyword,
      name: rt.payload.text,
      description: description,
      tags: build_tags(tags),
      children: children
    }

    {rule, after_children, errors}
  end

  # --- scenario / outline -----------------------------------------------------

  defp parse_scenario(head, tags, rest, language) do
    {description, after_desc} = take_description(rest, @scenario_desc_terminators)
    {steps, after_steps} = parse_steps(after_desc, language, [])
    {examples, after_examples} = parse_examples_blocks(after_steps, language, [])

    scenario = %Scenario{
      location: loc(head),
      keyword: head.payload.keyword,
      name: head.payload.text,
      description: description,
      tags: build_tags(tags),
      steps: steps,
      examples: examples
    }

    {scenario, after_examples}
  end

  defp parse_examples_blocks(tokens, language, acc) do
    {tags, after_tags} = take_tags(tokens)

    case after_tags do
      [%Token{type: :examples_line} = et | rest] ->
        {description, after_desc} = take_description(rest, @examples_desc_terminators)
        {header, body, after_table} = parse_examples_table(after_desc)

        examples = %Examples{
          location: loc(et),
          keyword: et.payload.keyword,
          name: et.payload.text,
          description: description,
          tags: build_tags(tags),
          table_header: header,
          table_body: body
        }

        parse_examples_blocks(after_table, language, [examples | acc])

      _ ->
        # Tags (if any) belong to the next sibling -> return the ORIGINAL stream.
        {Enum.reverse(acc), tokens}
    end
  end

  defp parse_examples_table(tokens) do
    case skip_blanks_and_comments(tokens) do
      [%Token{type: :table_row} = h | rest] ->
        header = table_row(h)
        {body, after_body} = take_table_rows(rest, [])
        {header, body, after_body}

      other ->
        {nil, [], other}
    end
  end

  # --- steps ------------------------------------------------------------------

  defp parse_steps(tokens, language, acc) do
    case skip_blanks_and_comments(tokens) do
      [%Token{type: :step_line} = st | rest] ->
        {arg, after_arg} = parse_step_arg(rest)

        step = %Step{
          location: loc(st),
          keyword: st.payload.keyword,
          keyword_type: keyword_type(st.payload.keyword, language, acc),
          text: st.payload.text,
          data_table: arg.data_table,
          doc_string: arg.doc_string
        }

        parse_steps(after_arg, language, [step | acc])

      _ ->
        {Enum.reverse(acc), tokens}
    end
  end

  defp parse_step_arg(tokens) do
    case skip_blanks_and_comments(tokens) do
      [%Token{type: :table_row} | _] = rows ->
        {table_rows, rest} = take_table_rows(rows, [])
        table = %DataTable{location: hd(table_rows).location, rows: table_rows}
        {%{data_table: table, doc_string: nil}, rest}

      [%Token{type: :doc_string_separator} = open | rest] ->
        {doc, after_doc} = parse_doc_string(open, rest)
        {%{data_table: nil, doc_string: doc}, after_doc}

      _ ->
        {%{data_table: nil, doc_string: nil}, tokens}
    end
  end

  # Doc string body is consumed verbatim until the matching closing fence. We do NOT
  # skip blanks/comments here: every line between the fences is content.
  defp parse_doc_string(open, tokens) do
    delim = open.payload.delimiter
    indent = open.column - 1
    {body_lines, after_close} = take_doc_body(tokens, delim, [])

    content =
      body_lines
      |> Enum.map(&dedent(&1, indent))
      |> Enum.join("\n")
      |> unescape_doc(delim)

    doc = %DocString{
      location: loc(open),
      media_type: open.payload.media_type,
      content: content,
      delimiter: delim
    }

    {doc, after_close}
  end

  defp take_doc_body([], _delim, acc), do: {Enum.reverse(acc), []}

  defp take_doc_body(
         [%Token{type: :doc_string_separator, payload: %{delimiter: d}} | rest],
         delim,
         acc
       )
       when d == delim,
       do: {Enum.reverse(acc), rest}

  defp take_doc_body([t | rest], delim, acc), do: take_doc_body(rest, delim, [t.raw | acc])

  defp dedent(line, 0), do: line

  defp dedent(line, indent) do
    {prefix, _} = String.split_at(line, indent)

    if String.trim(prefix) == "" do
      String.slice(line, min(indent, String.length(line))..-1//1) || ""
    else
      String.trim_leading(line)
    end
  end

  defp unescape_doc(content, "\"\"\""), do: String.replace(content, "\\\"\\\"\\\"", "\"\"\"")
  defp unescape_doc(content, "```"), do: String.replace(content, "\\`\\`\\`", "```")

  # --- tables -----------------------------------------------------------------

  defp take_table_rows(tokens, acc) do
    case skip_blanks_and_comments(tokens) do
      [%Token{type: :table_row} = r | rest] ->
        take_table_rows(rest, [table_row(r) | acc])

      _ ->
        {Enum.reverse(acc), tokens}
    end
  end

  defp table_row(%Token{} = t) do
    cells =
      Enum.map(t.payload.cells, fn c ->
        %TableCell{location: %Location{line: c.line, column: c.column}, value: c.value}
      end)

    %TableRow{location: loc(t), cells: cells}
  end

  # --- descriptions -----------------------------------------------------------

  # The official grammar's `DescriptionHelper := #Empty* Description?` with
  # `Description := (#Other | #Comment)+` is realised in the reference parser as a
  # per-context state machine: when a description is expected, every line that is NOT
  # one of the context's *terminator* tokens is consumed as description (#Other) —
  # including step-keyword-looking lines (`Given …`) and `*` bullets in
  # Feature/Rule-header position, which are description, not steps, there.
  #
  # The terminator set differs by context (mirrors the reference state machine):
  #
  #   * Feature / Rule header:  background, tag, scenario(+outline), rule lines
  #   * Background:             step, tag, scenario(+outline), rule lines
  #   * Scenario / Outline:     step, tag, examples, scenario(+outline), rule lines
  #   * Examples:               table_row, tag, examples, scenario(+outline), rule lines
  #
  # `:scenario_line` and `:scenario_outline_line` both terminate everywhere a scenario
  # would (the reference `match_ScenarioLine` matches both keywords). Leading `:empty`
  # lines are consumed and discarded; once a non-empty description line is seen, later
  # `:empty` lines are kept verbatim (their raw whitespace) and only trailing empties
  # are trimmed — exactly the reference AstBuilder Description behaviour. The terminator
  # sets themselves are module attributes declared near the top of the module.

  defp take_description(tokens, terminators) do
    {desc_tokens, rest} = take_description_lines(tokens, terminators, [], false)
    {format_description(desc_tokens), rest}
  end

  # `started?` tracks whether a non-empty (Other) description line has been seen yet.
  # Before that, leading `:empty` lines are dropped (DescriptionHelper's `#Empty*`).
  defp take_description_lines([], _terminators, acc, _started?), do: {Enum.reverse(acc), []}

  defp take_description_lines([%Token{type: :empty} = t | rest], terminators, acc, started?) do
    # Leading empties (before any Other) are discarded; interior ones are kept.
    acc = if started?, do: [t | acc], else: acc
    take_description_lines(rest, terminators, acc, started?)
  end

  defp take_description_lines([%Token{type: :comment} = t | rest], terminators, acc, started?) do
    # Comments live in the document-level comment list; they contribute no text but,
    # like the reference, do not toggle the started? flag (they aren't #Other).
    take_description_lines(rest, terminators, [t | acc], started?)
  end

  defp take_description_lines([%Token{type: type} | _] = toks, terminators, acc, _started?)
       when type in @all_desc_terminators do
    # Any terminator token ends the description; anything else is Other text.
    if type in terminators do
      {Enum.reverse(acc), toks}
    else
      [t | rest] = toks
      take_description_lines(rest, terminators, [t | acc], true)
    end
  end

  defp take_description_lines([%Token{} = t | rest], terminators, acc, _started?) do
    take_description_lines(rest, terminators, [t | acc], true)
  end

  # Description text: comment lines contribute nothing, trailing blank lines are
  # stripped (interior blanks already preserved). Each kept line is the FULL raw line
  # text (leading whitespace preserved, no trailing trim) — `getLineText(0)` in the
  # reference. The scanner has already stripped any trailing `\r`.
  defp format_description(tokens) do
    tokens
    |> Enum.reject(&(&1.type == :comment))
    |> Enum.map(& &1.raw)
    |> drop_trailing_blanks()
    |> Enum.join("\n")
  end

  defp drop_trailing_blanks(lines) do
    lines
    |> Enum.reverse()
    |> Enum.drop_while(&(String.trim(&1) == ""))
    |> Enum.reverse()
  end

  # --- step keyword type ------------------------------------------------------

  # The reference derives a step's keywordType purely from the keyword's dialect
  # group(s): given->Context, when->Action, then->Outcome, and/but->Conjunction. A
  # keyword that belongs to MORE THAN ONE group (notably `* `, which is an alias in
  # every group) is "Unknown" — there is no inheritance from the previous step.
  defp keyword_type(keyword, language, _prev) do
    types =
      [
        {:given, "Context"},
        {:when, "Action"},
        {:then, "Outcome"},
        {:and, "Conjunction"},
        {:but, "Conjunction"}
      ]
      |> Enum.filter(fn {group, _} -> keyword in Dialect.keywords!(language, group) end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()

    case types do
      [single] -> single
      _ -> "Unknown"
    end
  end

  # --- tags -------------------------------------------------------------------

  defp take_tags(tokens), do: take_tags_loop(skip_noise(tokens), [])

  defp take_tags_loop([%Token{type: :tag_line} = t | rest], acc) do
    take_tags_loop(skip_blanks_and_comments(rest), [t | acc])
  end

  defp take_tags_loop(tokens, acc) do
    tags = acc |> Enum.reverse() |> Enum.flat_map(& &1.payload.tags)
    {tags, tokens}
  end

  defp build_tags(raw_tags) do
    Enum.map(raw_tags, fn t ->
      %Tag{location: %Location{line: t.line, column: t.column}, name: t.name}
    end)
  end

  # --- validation (post-parse semantic errors) --------------------------------

  # Collected here so multiple errors (e.g. several inconsistent tables) surface in
  # source order, matching the reference parser's multi-error output.
  defp validate(%GherkinDocument{feature: nil}), do: []

  defp validate(%GherkinDocument{feature: feature}) do
    feature_tag_errors(feature.tags) ++ feature_table_errors(feature)
  end

  defp feature_tag_errors(_tags), do: []

  defp feature_table_errors(%Feature{children: children}) do
    Enum.flat_map(children, &child_table_errors/1)
  end

  defp child_table_errors({:background, %Background{steps: steps}}), do: steps_table_errors(steps)

  defp child_table_errors({:scenario, %Scenario{steps: steps, examples: examples}}) do
    steps_table_errors(steps) ++ Enum.flat_map(examples, &examples_table_errors/1)
  end

  defp child_table_errors({:rule, %Rule{children: children}}) do
    Enum.flat_map(children, &child_table_errors/1)
  end

  defp steps_table_errors(steps) do
    Enum.flat_map(steps, fn
      %Step{data_table: %DataTable{rows: rows}} -> table_rows_errors(rows)
      _ -> []
    end)
  end

  defp examples_table_errors(%Examples{table_header: nil}), do: []

  defp examples_table_errors(%Examples{table_header: header, table_body: body}) do
    table_rows_errors([header | body])
  end

  # The reference flags a row whose cell count differs from the FIRST row's. The
  # error points at the offending row's location.
  defp table_rows_errors([]), do: []

  defp table_rows_errors([first | _] = rows) do
    expected = length(first.cells)

    rows
    |> Enum.drop(1)
    |> Enum.filter(&(length(&1.cells) != expected))
    |> Enum.map(fn row ->
      loc = row.location
      msg = "inconsistent cell count within the table"
      {prefixed(msg, loc.line, loc.column), loc}
    end)
  end

  # --- errors -----------------------------------------------------------------

  defp unexpected(%Token{} = t, expected) do
    got = String.trim(t.raw)
    msg = "expected: #{Enum.join(expected, ", ")}, got '#{got}'"
    {prefixed(msg, t.line, t.column), Location.new(t.line, t.column)}
  end

  defp eof_error(%Token{} = last, expected) do
    line = last.line + 1
    msg = "unexpected end of file, expected: #{Enum.join(expected, ", ")}"
    {prefixed(msg, line, 0), %Location{line: line, column: nil}}
  end

  defp prefixed(message, line, column), do: "(#{line}:#{column}): #{message}"

  # --- misc -------------------------------------------------------------------

  defp loc(%Token{line: line, column: column}), do: %Location{line: line, column: column}

  defp skip_noise(tokens),
    do: Enum.drop_while(tokens, &(&1.type in [:empty, :comment, :language]))

  defp skip_blanks_and_comments(tokens),
    do: Enum.drop_while(tokens, &(&1.type in [:empty, :comment]))
end
