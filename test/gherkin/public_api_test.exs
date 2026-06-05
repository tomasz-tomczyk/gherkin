defmodule Gherkin.PublicApiTest do
  use ExUnit.Case, async: true

  alias Gherkin.AST.GherkinDocument
  alias Gherkin.{Pickle, PickleStep}

  @feature """
  @feat
  Feature: Coffee

    Background:
      Given the machine is on

    @sc
    Scenario: Buy coffee
      Given there are 3 coffees left
      When I press the button
      Then I am served a coffee

    Scenario Outline: Buy <count> coffees
      Given there are <count> coffees left
      Then I am served <count> coffees

      Examples:
        | count |
        | 1     |
        | 2     |
  """

  describe "parse/2" do
    test "returns {:ok, %GherkinDocument{}} for a well-formed feature via the new pipeline" do
      assert {:ok, %GherkinDocument{feature: feature}} = Gherkin.parse(@feature)
      assert feature.name == "Coffee"
      # The new AST keeps keyword trailing space (reference shape), proving this is
      # the AstParser pipeline and not the legacy parser.
      [{:background, _bg}, {:scenario, scenario}, {:scenario, _outline}] = feature.children
      assert scenario.name == "Buy coffee"
      assert [%{keyword: "Given "} | _] = scenario.steps
    end

    test "defaults to the AstParser pipeline WITHOUT any application config present" do
      # Mix does not load a dependency's config/config.exs, so the public API must not
      # depend on `config :gherkin, :pipeline, ...`. Prove the default works with the
      # env var cleared.
      previous = Application.get_env(:gherkin, :pipeline)
      Application.delete_env(:gherkin, :pipeline)

      try do
        assert {:ok, %GherkinDocument{feature: %{name: "Coffee"}}} = Gherkin.parse(@feature)
      after
        if previous, do: Application.put_env(:gherkin, :pipeline, previous)
      end
    end

    test "threads the :uri option onto the document" do
      assert {:ok, %GherkinDocument{uri: "features/coffee.feature"}} =
               Gherkin.parse(@feature, uri: "features/coffee.feature")
    end

    test "returns {:error, errors} for malformed input" do
      assert {:error, [{message, _location} | _]} = Gherkin.parse("not a feature at all")
      assert is_binary(message)
    end
  end

  describe "parse!/2" do
    test "returns the document directly on success" do
      assert %GherkinDocument{feature: %{name: "Coffee"}} = Gherkin.parse!(@feature)
    end

    test "raises Gherkin.ParseError on malformed input" do
      assert_raise Gherkin.ParseError, fn -> Gherkin.parse!("not a feature at all") end
    end
  end

  describe "pickles/2" do
    test "compiles a feature into fully-resolved pickles" do
      pickles = Gherkin.pickles(@feature)

      # Plain scenario + 2 outline rows = 3 pickles.
      assert [buy, row1, row2] = pickles
      assert %Pickle{name: "Buy coffee"} = buy
      assert %Pickle{name: "Buy 1 coffees"} = row1
      assert %Pickle{name: "Buy 2 coffees"} = row2
    end

    test "prepends background steps to each pickle" do
      [buy | _] = Gherkin.pickles(@feature)

      assert [
               %PickleStep{text: "the machine is on"},
               %PickleStep{text: "there are 3 coffees left"},
               %PickleStep{text: "I press the button"},
               %PickleStep{text: "I am served a coffee"}
             ] = buy.steps
    end

    test "substitutes outline placeholders in steps" do
      [_buy, row1, _row2] = Gherkin.pickles(@feature)

      assert [
               %PickleStep{text: "the machine is on"},
               %PickleStep{text: "there are 1 coffees left"},
               %PickleStep{text: "I am served 1 coffees"}
             ] = row1.steps
    end

    test "inherits and unions tags from feature and scenario" do
      [buy | _] = Gherkin.pickles(@feature)
      names = Enum.map(buy.tags, & &1.name)
      assert "@feat" in names
      assert "@sc" in names
    end

    test "threads the :uri option onto each pickle" do
      [pickle | _] = Gherkin.pickles(@feature, uri: "features/coffee.feature")
      assert pickle.uri == "features/coffee.feature"
    end

    test "returns [] for an empty document" do
      assert [] = Gherkin.pickles("# just a comment\n")
    end

    test "raises Gherkin.ParseError on malformed input" do
      assert_raise Gherkin.ParseError, fn -> Gherkin.pickles("not a feature at all") end
    end
  end
end
