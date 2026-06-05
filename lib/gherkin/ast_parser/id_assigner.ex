defmodule Gherkin.AstParser.IdAssigner do
  @moduledoc """
  Assigns string ids to AST nodes in the exact order the reference cucumber
  `AstBuilder` does, so emitted ids match the golden NDJSON byte-for-byte.

  The reference builder numbers nodes **post-order**: a node's descendants and its
  tags are numbered before the node itself, and the node's children come before its
  tags. Concretely, for each construct the order is:

    * Step: data-table rows (each), then the step.
    * Background: steps (with their table rows), then the background.
    * Scenario: steps, then for each Examples (header row, body rows, examples tags,
      examples), then the scenario's tags, then the scenario.
    * Rule: children (each), then the rule's tags, then the rule.
    * Feature: children (each), then the feature's tags. (Feature itself has no id.)

  Only `Tag`, `Step`, `Background`, `Scenario`, `Examples`, `Rule`, and `TableRow`
  (data-table rows + examples header/body rows) carry ids. The document, feature,
  data-table container, and table cells do not.
  """

  alias Gherkin.AST.{
    Background,
    DataTable,
    Examples,
    Feature,
    GherkinDocument,
    Rule,
    Scenario,
    Step,
    TableRow
  }

  @doc "Return `doc` with every id-bearing node assigned a sequential string id."
  @spec assign(GherkinDocument.t()) :: GherkinDocument.t()
  def assign(%GherkinDocument{feature: nil} = doc), do: doc

  def assign(%GherkinDocument{feature: feature} = doc) do
    {feature, _next} = number_feature(feature, 0)
    %{doc | feature: feature}
  end

  defp number_feature(%Feature{} = feature, counter) do
    {children, counter} = number_children(feature.children, counter, [])
    {tags, counter} = number_tags(feature.tags, counter)
    {%{feature | children: children, tags: tags}, counter}
  end

  defp number_children([], counter, acc), do: {Enum.reverse(acc), counter}

  defp number_children([{:background, bg} | rest], counter, acc) do
    {bg, counter} = number_background(bg, counter)
    number_children(rest, counter, [{:background, bg} | acc])
  end

  defp number_children([{:scenario, sc} | rest], counter, acc) do
    {sc, counter} = number_scenario(sc, counter)
    number_children(rest, counter, [{:scenario, sc} | acc])
  end

  defp number_children([{:rule, rule} | rest], counter, acc) do
    {rule, counter} = number_rule(rule, counter)
    number_children(rest, counter, [{:rule, rule} | acc])
  end

  defp number_rule(%Rule{} = rule, counter) do
    {children, counter} = number_children(rule.children, counter, [])
    {tags, counter} = number_tags(rule.tags, counter)
    {id, counter} = next(counter)
    {%{rule | children: children, tags: tags, id: id}, counter}
  end

  defp number_background(%Background{} = bg, counter) do
    {steps, counter} = number_steps(bg.steps, counter, [])
    {id, counter} = next(counter)
    {%{bg | steps: steps, id: id}, counter}
  end

  defp number_scenario(%Scenario{} = sc, counter) do
    {steps, counter} = number_steps(sc.steps, counter, [])
    {examples, counter} = number_examples_list(sc.examples, counter, [])
    {tags, counter} = number_tags(sc.tags, counter)
    {id, counter} = next(counter)
    {%{sc | steps: steps, examples: examples, tags: tags, id: id}, counter}
  end

  defp number_steps([], counter, acc), do: {Enum.reverse(acc), counter}

  defp number_steps([%Step{} = step | rest], counter, acc) do
    {data_table, counter} = number_data_table(step.data_table, counter)
    {id, counter} = next(counter)
    step = %{step | data_table: data_table, id: id}
    number_steps(rest, counter, [step | acc])
  end

  defp number_data_table(nil, counter), do: {nil, counter}

  defp number_data_table(%DataTable{rows: rows} = table, counter) do
    {rows, counter} = number_rows(rows, counter, [])
    {%{table | rows: rows}, counter}
  end

  defp number_examples_list([], counter, acc), do: {Enum.reverse(acc), counter}

  defp number_examples_list([%Examples{} = ex | rest], counter, acc) do
    {ex, counter} = number_examples(ex, counter)
    number_examples_list(rest, counter, [ex | acc])
  end

  defp number_examples(%Examples{} = ex, counter) do
    {header, counter} = number_optional_row(ex.table_header, counter)
    {body, counter} = number_rows(ex.table_body, counter, [])
    {tags, counter} = number_tags(ex.tags, counter)
    {id, counter} = next(counter)
    {%{ex | table_header: header, table_body: body, tags: tags, id: id}, counter}
  end

  defp number_optional_row(nil, counter), do: {nil, counter}
  defp number_optional_row(%TableRow{} = row, counter), do: number_row(row, counter)

  defp number_rows([], counter, acc), do: {Enum.reverse(acc), counter}

  defp number_rows([row | rest], counter, acc) do
    {row, counter} = number_row(row, counter)
    number_rows(rest, counter, [row | acc])
  end

  defp number_row(%TableRow{} = row, counter) do
    {id, counter} = next(counter)
    {%{row | id: id}, counter}
  end

  defp number_tags(tags, counter) do
    Enum.map_reduce(tags, counter, fn tag, c ->
      {id, c} = next(c)
      {%{tag | id: id}, c}
    end)
  end

  defp next(counter), do: {Integer.to_string(counter), counter + 1}
end
