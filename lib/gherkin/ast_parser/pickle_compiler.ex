defmodule Gherkin.AstParser.PickleCompiler do
  @moduledoc """
  Compiles an id-assigned `Gherkin.AST.GherkinDocument` into a list of
  `Gherkin.Pickle` — the AST → pickles stage of the reference pipeline.

  ## What compilation does

    * **One pickle per Scenario**, and **one pickle per Examples body row** of a
      Scenario Outline (the header row names the params; each body row → one pickle).
      A Scenario with no steps still produces a pickle (with `steps: []`).
    * **Background steps are prepended** to every pickle in scope: a Feature-level
      Background applies to all scenarios; a Rule-level Background applies only to
      scenarios in that Rule, *after* the feature background.
    * **Tags are inherited and unioned** onto each pickle in source order:
      Feature → Rule → Scenario/Outline → (for outline rows) the Examples block.
    * **`<placeholder>` substitution** for outlines: the Examples header→row mapping
      is applied to step text, data-table cells, and doc-string content + media type.
    * **Conjunction resolution**: `And`/`But`/`*`-derived `Conjunction` step types
      resolve to the type of the preceding non-conjunction step.

  ## Id scheme (distinct from AST ids)

  Pickle ids continue a single counter that starts where the AST id counter stopped
  (i.e. `max(AST id) + 1`). Pickles are emitted in document order; for each pickle,
  every one of its steps is numbered first (prepended background steps before the
  scenario's own steps), then the pickle itself. This matches the reference
  `Compiler`'s emission order byte-for-byte.

  `ast_node_ids`:

    * pickle: `[scenario_id]` for a plain scenario; `[scenario_id, examples_row_id]`
      for an outline row.
    * pickle step: `[step_id]` for a plain step; `[step_id, examples_row_id]` for an
      outline-expanded step.
  """

  alias Gherkin.AST.{Background, Examples, Feature, GherkinDocument, Rule, Scenario, Step}
  alias Gherkin.{Pickle, PickleStep}

  @doc "Compile an id-assigned document into its list of pickles (document order)."
  @spec compile(GherkinDocument.t()) :: [Pickle.t()]
  def compile(%GherkinDocument{feature: nil}), do: []

  def compile(%GherkinDocument{feature: %Feature{} = feature, uri: uri}) do
    counter = next_id_seed(feature)
    language = feature.language

    ctx = %{
      uri: uri,
      language: language,
      feature_tags: feature.tags,
      feature_bg_steps: background_steps(feature.children)
    }

    {pickles, _counter} = compile_children(feature.children, ctx, counter, [])
    Enum.reverse(pickles)
  end

  # --- child traversal -------------------------------------------------------

  defp compile_children([], _ctx, counter, acc), do: {acc, counter}

  defp compile_children([{:background, _bg} | rest], ctx, counter, acc) do
    compile_children(rest, ctx, counter, acc)
  end

  defp compile_children([{:scenario, %Scenario{} = sc} | rest], ctx, counter, acc) do
    {acc, counter} =
      compile_scenario(sc, ctx.feature_bg_steps, ctx.feature_tags, ctx, counter, acc)

    compile_children(rest, ctx, counter, acc)
  end

  defp compile_children([{:rule, %Rule{} = rule} | rest], ctx, counter, acc) do
    rule_bg_steps = ctx.feature_bg_steps ++ background_steps(rule.children)
    rule_tags = ctx.feature_tags ++ rule.tags

    {acc, counter} =
      Enum.reduce(rule.children, {acc, counter}, fn
        {:scenario, %Scenario{} = sc}, {acc, counter} ->
          compile_scenario(sc, rule_bg_steps, rule_tags, ctx, counter, acc)

        {:background, _bg}, {acc, counter} ->
          {acc, counter}
      end)

    compile_children(rest, ctx, counter, acc)
  end

  # --- scenario compilation --------------------------------------------------

  defp compile_scenario(%Scenario{examples: []} = sc, bg_steps, inherited_tags, ctx, counter, acc) do
    tags = inherited_tags ++ sc.tags
    {steps, counter} = compile_steps(bg_steps, sc.steps, nil, counter)
    {id, counter} = next(counter)

    pickle = %Pickle{
      id: id,
      uri: ctx.uri,
      name: sc.name,
      language: ctx.language,
      location: sc.location,
      steps: steps,
      tags: pickle_tags(tags),
      ast_node_ids: [sc.id]
    }

    {[pickle | acc], counter}
  end

  defp compile_scenario(%Scenario{} = sc, bg_steps, inherited_tags, ctx, counter, acc) do
    Enum.reduce(sc.examples, {acc, counter}, fn %Examples{} = ex, {acc, counter} ->
      params = header_params(ex)
      ex_tags = inherited_tags ++ sc.tags ++ ex.tags

      Enum.reduce(ex.table_body, {acc, counter}, fn row, {acc, counter} ->
        mapping = row_mapping(params, row)
        {steps, counter} = compile_steps(bg_steps, sc.steps, {mapping, row.id}, counter)
        {id, counter} = next(counter)

        pickle = %Pickle{
          id: id,
          uri: ctx.uri,
          name: substitute(sc.name, mapping),
          language: ctx.language,
          location: row.location,
          steps: steps,
          tags: pickle_tags(ex_tags),
          ast_node_ids: [sc.id, row.id]
        }

        {[pickle | acc], counter}
      end)
    end)
  end

  # --- step compilation ------------------------------------------------------

  # A scenario with no steps of its own produces an empty pickle: the reference does
  # NOT prepend background steps (a background alone never makes a pickle runnable),
  # and no step ids are consumed.
  defp compile_steps(_bg_steps, [], _expansion, counter), do: {[], counter}

  # `expansion` is nil for a plain scenario, or {mapping, row_id} for an outline row.
  defp compile_steps(bg_steps, scenario_steps, expansion, counter) do
    # Background steps are never substituted (they have no outline params), but they
    # do participate in conjunction-type resolution alongside the scenario's steps.
    all = Enum.map(bg_steps, &{&1, nil}) ++ Enum.map(scenario_steps, &{&1, expansion})

    {steps, counter, _last_type} =
      Enum.reduce(all, {[], counter, "Unknown"}, fn {step, exp}, {acc, counter, last_type} ->
        type = resolve_type(step.keyword_type, last_type)
        {id, counter} = next(counter)
        {pstep, counter} = build_step(step, exp, type, id, counter)
        next_last = if step.keyword_type == "Conjunction", do: last_type, else: type
        {[pstep | acc], counter, next_last}
      end)

    {Enum.reverse(steps), counter}
  end

  defp build_step(%Step{} = step, expansion, type, id, counter) do
    {mapping, row_id} =
      case expansion do
        nil -> {nil, nil}
        {mapping, row_id} -> {mapping, row_id}
      end

    ast_node_ids = if row_id, do: [step.id, row_id], else: [step.id]

    pstep = %PickleStep{
      id: id,
      text: substitute(step.text, mapping),
      type: type,
      argument: pickle_argument(step, mapping),
      ast_node_ids: ast_node_ids
    }

    {pstep, counter}
  end

  defp pickle_argument(%Step{data_table: nil, doc_string: nil}, _mapping), do: nil

  defp pickle_argument(%Step{data_table: %{rows: rows}}, mapping) do
    rows =
      Enum.map(rows, fn row ->
        Enum.map(row.cells, fn cell -> substitute(cell.value, mapping) end)
      end)

    {:data_table, %Pickle.DataTable{rows: rows}}
  end

  defp pickle_argument(%Step{doc_string: ds}, mapping) when not is_nil(ds) do
    {:doc_string,
     %Pickle.DocString{
       content: substitute(ds.content, mapping),
       media_type: ds.media_type && substitute(ds.media_type, mapping)
     }}
  end

  # --- conjunction resolution ------------------------------------------------

  defp resolve_type("Conjunction", last_type), do: last_type
  defp resolve_type(nil, last_type), do: last_type
  defp resolve_type(type, _last_type), do: type

  # --- placeholder substitution ----------------------------------------------

  defp substitute(text, nil), do: text

  defp substitute(text, mapping) do
    Enum.reduce(mapping, text, fn {name, value}, acc ->
      String.replace(acc, "<#{name}>", value)
    end)
  end

  defp header_params(%Examples{table_header: nil}), do: []

  defp header_params(%Examples{table_header: header}),
    do: Enum.map(header.cells, & &1.value)

  defp row_mapping(params, row) do
    params
    |> Enum.zip(Enum.map(row.cells, & &1.value))
  end

  # --- tags ------------------------------------------------------------------

  defp pickle_tags(tags) do
    Enum.map(tags, fn tag -> %Pickle.Tag{name: tag.name, ast_node_id: tag.id} end)
  end

  # --- backgrounds -----------------------------------------------------------

  defp background_steps(children) do
    Enum.find_value(children, [], fn
      {:background, %Background{steps: steps}} -> steps
      _ -> false
    end)
  end

  # --- id counter ------------------------------------------------------------

  # The pickle counter starts at max(AST id) + 1. We recover it by walking the
  # already-id-assigned feature for the highest numeric id.
  defp next_id_seed(%Feature{} = feature) do
    max = max_id(feature, -1)
    max + 1
  end

  defp max_id(value, acc) when is_struct(value) do
    value
    |> Map.from_struct()
    |> Enum.reduce(acc_id(value, acc), fn {_k, v}, acc -> max_id(v, acc) end)
  end

  defp max_id(value, acc) when is_list(value) do
    Enum.reduce(value, acc, &max_id/2)
  end

  defp max_id({_tag, value}, acc), do: max_id(value, acc)
  defp max_id(_other, acc), do: acc

  defp acc_id(%{id: id}, acc) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> max(n, acc)
      _ -> acc
    end
  end

  defp acc_id(_value, acc), do: acc

  defp next(counter), do: {Integer.to_string(counter), counter + 1}
end
