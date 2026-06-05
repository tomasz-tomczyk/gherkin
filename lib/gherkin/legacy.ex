defmodule Gherkin.Legacy do
  @moduledoc """
  The original line-based Gherkin parser, preserved for backwards compatibility.

  This is the parser that used to back `Gherkin.parse/1`. It produces the
  `Gherkin.Elements.*` structs and is intentionally *not* cucumber-messages
  conformant (no ids, no `keyword_type`, partial Rule support, `(Example N)`
  scenario naming).

  New code should use the public `Gherkin` API (`Gherkin.parse/2`,
  `Gherkin.pickles/2`), which is backed by the conformant `Gherkin.AstParser`
  pipeline. This module exists only so existing callers of the legacy element
  structs keep working during migration.
  """

  alias Gherkin.Elements.{Feature, Scenario, ScenarioOutline}
  alias Gherkin.Parser

  @doc """
  Parse a binary or file stream with the legacy parser.

  Example:

      iex> "test/fixtures/coffee.feature" |> File.read!() |> Gherkin.Legacy.parse()
      %Gherkin.Elements.Feature{
        description: "As a Barrista
      Coffee should not be served until paid for
      Coffee should not be served until the button has been pressed
      If there is no coffee left then money should be refunded
      ",
        line: 1,
        name: "Serve coffee",
        scenarios: [
          %Gherkin.Elements.Scenario{
            line: 7,
            name: "Buy last coffee",
            steps: [
              %Gherkin.Elements.Step{
                keyword: "Given",
                line: 8,
                text: "there are 1 coffees left in the machine"
              }
            ],
          }
        ],
      }
  """
  def parse(string_or_stream) do
    Parser.parse_feature(string_or_stream)
  end

  @doc """
  Parse a file by relative path with the legacy parser.

  Example:

      iex> Gherkin.Legacy.parse_file("test/fixtures/coffee.feature")
      %Gherkin.Elements.Feature{
        description: "As a Barrista
      Coffee should not be served until paid for
      Coffee should not be served until the button has been pressed
      If there is no coffee left then money should be refunded
      ",
        file: "test/fixtures/coffee.feature",
        line: 1,
        name: "Serve coffee",
        scenarios: [
          %Gherkin.Elements.Scenario{
            line: 7,
            name: "Buy last coffee",
            steps: [
              %Gherkin.Elements.Step{
                keyword: "Given",
                line: 8,
                text: "there are 1 coffees left in the machine"
              }
            ],
          }
        ],
      }
  """
  def parse_file(file_name) do
    file_name
    |> File.read!()
    |> Parser.parse_feature(file_name)
  end

  @doc """
  Given a `Gherkin.Elements.Feature`, changes all `Gherkin.Elements.ScenarioOutline`s
  into `Gherkin.Elements.Scenario` as a flattened list of scenarios.
  """
  def flatten(feature = %Feature{scenarios: scenarios}) do
    %{
      feature
      | scenarios:
          scenarios
          |> Enum.map(fn
            # Nothing to do
            scenario = %Scenario{} -> scenario
            outline = %ScenarioOutline{} -> scenarios_for(outline)
          end)
          |> List.flatten()
    }
  end

  @doc """
  Changes a `Gherkin.Elements.ScenarioOutline` into multiple `Gherkin.Elements.Scenario`s
  so that they may be executed in the same manner.

  Given an outline, its easy to run all scenarios:

      outline = %Gherkin.Elements.ScenarioOutline{}
      Gherkin.Legacy.scenarios_for(outline) |> Enum.each(&run_scenario/1)
  """
  def scenarios_for(%ScenarioOutline{
        name: name,
        tags: tags,
        steps: steps,
        examples: examples,
        line: line
      }) do
    examples
    |> Enum.with_index(1)
    |> Enum.map(fn {example, index} ->
      %Scenario{
        name: name <> " (Example #{index})",
        tags: tags,
        line: line,
        steps:
          Enum.map(steps, fn step ->
            %{
              step
              | text:
                  Enum.reduce(example, step.text, fn {k, v}, t ->
                    String.replace(t, ~r/<#{k}>/, v)
                  end)
            }
          end)
      }
    end)
  end
end
