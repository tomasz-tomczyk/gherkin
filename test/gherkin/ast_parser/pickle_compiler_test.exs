defmodule Gherkin.AstParser.PickleCompilerTest do
  use ExUnit.Case, async: true

  alias Gherkin.AstParser
  alias Gherkin.AstParser.PickleCompiler
  alias Gherkin.{Pickle, PickleStep}

  defp compile!(data) do
    {:ok, doc} = AstParser.parse("x.feature", data)
    PickleCompiler.compile(doc)
  end

  describe "basic emission" do
    test "one pickle per scenario, with its own steps" do
      assert [%Pickle{name: "minimalistic", steps: [step], tags: []}] =
               compile!("""
               Feature: Minimal

                 Scenario: minimalistic
                   Given the minimalism
               """)

      assert %PickleStep{text: "the minimalism", type: "Context"} = step
    end

    test "no feature yields no pickles" do
      {:ok, doc} = AstParser.parse("x", "")
      assert PickleCompiler.compile(doc) == []
    end

    test "pickle and step ids continue the AST id counter (post-order)" do
      # AST ids: step=0, scenario=1 -> pickle counter seeds at 2.
      assert [%Pickle{id: "3", steps: [%PickleStep{id: "2"}], ast_node_ids: ["1"]}] =
               compile!("""
               Feature: F

                 Scenario: s
                   Given a
               """)
    end
  end

  describe "backgrounds" do
    test "feature background steps are prepended to every scenario" do
      [p1, p2] =
        compile!("""
        Feature: F

          Background:
            Given bg

          Scenario: one
            Given a

          Scenario: two
            Given b
        """)

      assert Enum.map(p1.steps, & &1.text) == ["bg", "a"]
      assert Enum.map(p2.steps, & &1.text) == ["bg", "b"]
    end

    test "rule background follows the feature background, scoped to the rule" do
      [p] =
        compile!("""
        Feature: F

          Background:
            Given fb

          Rule: R
            Background:
              Given rb

            Example: ex
              Given a
        """)

      assert Enum.map(p.steps, & &1.text) == ["fb", "rb", "a"]
    end

    test "a scenario with no steps produces an empty pickle (background not prepended)" do
      [p] =
        compile!("""
        Feature: F

          Background:
            Given bg

          Scenario: no steps
        """)

      assert p.steps == []
      # the empty pickle consumes no step ids: bg-step=0, bg=1, scenario=2 -> pickle=3
      assert p.id == "3"
      assert p.ast_node_ids == ["2"]
    end
  end

  describe "scenario outlines" do
    test "one pickle per examples body row, with placeholder substitution" do
      [p1, p2] =
        compile!("""
        Feature: F

          Scenario Outline: o
            Given the <what>

            Examples:
              | what  |
              | one   |
              | two   |
        """)

      assert [%PickleStep{text: "the one"}] = p1.steps
      assert [%PickleStep{text: "the two"}] = p2.steps
    end

    test "pickle and step astNodeIds carry the examples row id for outlines" do
      [p] =
        compile!("""
        Feature: F

          Scenario Outline: o
            Given the <what>

            Examples:
              | what |
              | x    |
        """)

      [scenario_id, row_id] = p.ast_node_ids
      assert [%PickleStep{ast_node_ids: [_step_id, ^row_id]}] = p.steps
      assert scenario_id != row_id
    end

    test "an outline with no examples behaves like a plain scenario" do
      [p] =
        compile!("""
        Feature: F

          Scenario Outline: o
            Given a step
        """)

      assert [%PickleStep{text: "a step"}] = p.steps
      assert length(p.ast_node_ids) == 1
    end

    test "examples with a header but no body rows produce no pickle" do
      assert compile!("""
             Feature: F

               Scenario Outline: o

                 Examples:
                 | what |
             """) == []
    end

    test "substitution applies to the scenario name" do
      [p] =
        compile!("""
        Feature: F

          Scenario Outline: greet <who>
            Given hi <who>

            Examples:
              | who   |
              | world |
        """)

      assert p.name == "greet world"
    end
  end

  describe "tag inheritance and union" do
    test "feature, scenario tags are unioned in source order" do
      [p] =
        compile!("""
        @feat
        Feature: F

          @scen
          Scenario: s
            Given a
        """)

      assert Enum.map(p.tags, & &1.name) == ["@feat", "@scen"]
    end

    test "outline rows union feature, outline and the specific examples block tags" do
      [p1, p2] =
        compile!("""
        @feat
        Feature: F

          @outline
          Scenario Outline: o
            Given <x>

            @first
            Examples:
              | x |
              | 1 |

            @second
            Examples:
              | x |
              | 2 |
        """)

      assert Enum.map(p1.tags, & &1.name) == ["@feat", "@outline", "@first"]
      assert Enum.map(p2.tags, & &1.name) == ["@feat", "@outline", "@second"]
    end

    test "rule tags are inherited by the rule's scenarios" do
      [p] =
        compile!("""
        @feat
        Feature: F

          @rule
          Rule: R
            @scen
            Example: ex
              Given a
        """)

      assert Enum.map(p.tags, & &1.name) == ["@feat", "@rule", "@scen"]
    end
  end

  describe "conjunction resolution" do
    test "And/But inherit the preceding non-conjunction step type" do
      [p] =
        compile!("""
        Feature: F

          Scenario: s
            Given a
            And b
            When c
            But d
            Then e
            And f
        """)

      assert Enum.map(p.steps, & &1.type) ==
               ["Context", "Context", "Action", "Action", "Outcome", "Outcome"]
    end

    test "star keyword steps resolve to Unknown, and so do their conjunctions" do
      [p] =
        compile!("""
        Feature: F

          Scenario: s
            * a
            And b
        """)

      assert Enum.map(p.steps, & &1.type) == ["Unknown", "Unknown"]
    end
  end

  describe "step arguments" do
    test "data table cells are substituted and projected without ids/locations" do
      [p] =
        compile!("""
        Feature: F

          Scenario Outline: o
            Given a table
              | col | <x> |

            Examples:
              | x   |
              | val |
        """)

      assert [%PickleStep{argument: {:data_table, %Pickle.DataTable{rows: rows}}}] = p.steps
      assert rows == [["col", "val"]]
    end

    test "doc string content and media type are substituted" do
      [p] =
        compile!("""
        Feature: F

          Scenario Outline: o
            Given a doc
              \"\"\"<type>
              hello <name>
              \"\"\"

            Examples:
              | type | name  |
              | md   | world |
        """)

      assert [%PickleStep{argument: {:doc_string, ds}}] = p.steps
      assert ds.content == "hello world"
      assert ds.media_type == "md"
    end
  end
end
