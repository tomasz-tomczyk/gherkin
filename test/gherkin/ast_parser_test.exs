defmodule Gherkin.AstParserTest do
  use ExUnit.Case, async: true

  alias Gherkin.AST.{Background, Examples, Feature, GherkinDocument, Rule, Scenario, Step}
  alias Gherkin.AstParser

  defp parse!(data) do
    {:ok, doc} = AstParser.parse("x.feature", data)
    doc
  end

  describe "minimal documents" do
    test "feature + scenario + step" do
      doc =
        parse!("""
        Feature: Minimal

          Scenario: minimalistic
            Given the minimalism
        """)

      assert %GherkinDocument{feature: %Feature{name: "Minimal", children: children}} = doc
      assert [{:scenario, %Scenario{name: "minimalistic", steps: [step]}}] = children
      assert %Step{keyword: "Given ", keyword_type: "Context", text: "the minimalism"} = step
    end

    test "empty input yields a document with no feature" do
      assert {:ok, %GherkinDocument{feature: nil, comments: []}} = AstParser.parse("x", "")
    end
  end

  describe "id assignment matches the reference post-order numbering" do
    test "background steps and scenarios interleave ids" do
      doc =
        parse!("""
        Feature: Background

          Background: bg
            Given a

          Scenario: one
            Given b
        """)

      [{:background, bg}, {:scenario, sc}] = doc.feature.children
      [bg_step] = bg.steps
      [sc_step] = sc.steps
      assert {bg_step.id, bg.id} == {"0", "1"}
      assert {sc_step.id, sc.id} == {"2", "3"}
    end

    test "feature tags are numbered last" do
      doc =
        parse!("""
        @ft
        Feature: F

          Scenario: s
            Given a
        """)

      [%{id: feature_tag_id}] = doc.feature.tags
      [{:scenario, sc}] = doc.feature.children
      # step 0, scenario 1, feature tag 2 (numbered after all children).
      assert {hd(sc.steps).id, sc.id, feature_tag_id} == {"0", "1", "2"}
    end

    test "scenario outline examples rows and tags get ids in source order" do
      doc =
        parse!("""
        Feature: F

          Scenario Outline: o
            Given the <what>

            @ex
            Examples:
              | what |
              | foo  |
        """)

      [{:scenario, %Scenario{examples: [%Examples{} = ex]} = sc}] = doc.feature.children
      # step 0, header 1, body 2, @ex tag 3, examples 4, scenario 5
      assert hd(sc.steps).id == "0"
      assert ex.table_header.id == "1"
      assert hd(ex.table_body).id == "2"
      assert hd(ex.tags).id == "3"
      assert ex.id == "4"
      assert sc.id == "5"
    end
  end

  describe "rules" do
    test "a rule collects its own backgrounds and scenarios" do
      doc =
        parse!("""
        Feature: F

          Rule: R
            Background: rb
              Given a

            Example: e
              Given b
        """)

      [{:rule, %Rule{name: "R", children: rule_children}}] = doc.feature.children
      assert [{:background, %Background{}}, {:scenario, %Scenario{}}] = rule_children
    end
  end

  describe "doc strings" do
    test "dedents by the opening fence column and captures the media type" do
      doc =
        parse!("""
        Feature: F

          Scenario: s
            Given a
              \"\"\"json
              {"a": 1}
                indented
              \"\"\"
        """)

      [{:scenario, %Scenario{steps: [step]}}] = doc.feature.children
      assert step.doc_string.media_type == "json"
      assert step.doc_string.content == "{\"a\": 1}\n  indented"
    end
  end

  describe "errors" do
    test "unknown language" do
      assert {:error, [{msg, _loc}]} = AstParser.parse("x", "# language: zzz\n")
      assert msg == "(1:1): Language not supported: zzz"
    end

    test "inconsistent cell count points at the offending row" do
      data = """
      Feature: F

        Scenario: s
          Given a
            | a | b |
            | c |
      """

      assert {:error, [{msg, loc}]} = AstParser.parse("x", data)
      assert msg =~ "inconsistent cell count within the table"
      assert loc.line == 6
    end

    test "whitespace in tags" do
      data = """
      Feature: F

        @a tag with spaces
        Scenario: s
          Given a
      """

      assert {:error, errors} = AstParser.parse("x", data)
      assert Enum.any?(errors, fn {m, _} -> m =~ "A tag may not contain whitespace" end)
    end

    test "recovers and reports multiple errors in source order" do
      data = """

      junk before feature

      Feature: F

        Scenario: s
          Given a

      junk after scenario
      """

      assert {:error, errors} = AstParser.parse("x", data)
      lines = Enum.map(errors, fn {_m, loc} -> loc.line end)
      assert lines == Enum.sort(lines)
      assert length(errors) >= 2
    end

    test "unterminated doc string at EOF" do
      data = """
      Feature: F
      Scenario: s
        Given a
          \"\"\"
      """

      assert {:error, [{msg, _loc}]} = AstParser.parse("x", data)
      assert msg =~ "unexpected end of file, expected: #DocStringSeparator, #Other"
    end
  end
end
