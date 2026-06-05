defmodule Gherkin.GherkinTest do
  use ExUnit.Case

  alias Gherkin.AST.GherkinDocument

  doctest Gherkin

  @file_name "test/fixtures/coffee.feature"

  test "parse/2 parses a fixture file via the public API" do
    assert {:ok, %GherkinDocument{uri: @file_name, feature: feature}} =
             @file_name |> File.read!() |> Gherkin.parse(uri: @file_name)

    assert feature.name == "Serve coffee"
  end

  @outline """
  Feature: Serve coffee

    Scenario Outline: Buy coffee
      Given there are <coffees> coffees left in the machine
      And I have deposited $<money>
      When I press the coffee button
      Then I should be served <served> coffees

      Examples:
        | coffees | money | served |
        |  12     |  6    |  12    |
        |  2      |  3    |  2     |
  """

  test "pickles/2 expands a scenario outline into one pickle per example row" do
    assert [row1, row2] = Gherkin.pickles(@outline)

    assert Enum.map(row1.steps, & &1.text) == [
             "there are 12 coffees left in the machine",
             "I have deposited $6",
             "I press the coffee button",
             "I should be served 12 coffees"
           ]

    assert Enum.map(row2.steps, & &1.text) == [
             "there are 2 coffees left in the machine",
             "I have deposited $3",
             "I press the coffee button",
             "I should be served 2 coffees"
           ]
  end
end
