defmodule Gherkin.AstParser.ScannerTest do
  use ExUnit.Case, async: true

  alias Gherkin.AstParser.Scanner

  defp types(data) do
    {:ok, tokens, _lang} = Scanner.scan(data)
    Enum.map(tokens, & &1.type)
  end

  defp tokens(data) do
    {:ok, tokens, _lang} = Scanner.scan(data)
    tokens
  end

  describe "line classification" do
    test "classifies the canonical line kinds" do
      data = """
      Feature: F
        Scenario: S
          Given a step
          | a | b |
      """

      assert types(data) == [:feature_line, :scenario_line, :step_line, :table_row]
    end

    test "blank, comment and tag lines" do
      assert types("\n# a comment\n@x @y\n") == [:empty, :comment, :tag_line]
    end

    test "scenario outline wins over scenario (longest keyword)" do
      assert [:scenario_outline_line] = types("Scenario Outline: o")
    end

    test "doc-string fences of both flavours" do
      assert types("\"\"\"\n```\n") == [:doc_string_separator, :doc_string_separator]
    end
  end

  describe "locations" do
    test "1-indexed line and first-non-space column" do
      [feature, scenario, step] = tokens("Feature: F\n  Scenario: S\n    Given a")
      assert {feature.line, feature.column} == {1, 1}
      assert {scenario.line, scenario.column} == {2, 3}
      assert {step.line, step.column} == {3, 5}
    end

    test "strips a trailing carriage return (CRLF input)" do
      [t] = tokens("Feature: F\r")
      assert t.raw == "Feature: F"
      assert t.type == :feature_line
    end
  end

  describe "language header" do
    test "honours a # language: header" do
      {:ok, _tokens, lang} = Scanner.scan("# language: fr\nFonctionnalité: x")
      assert lang == "fr"
    end

    test "header without spaces" do
      {:ok, _tokens, lang} = Scanner.scan("#language:no\n")
      assert lang == "no"
    end

    test "defaults to en" do
      {:ok, _tokens, lang} = Scanner.scan("Feature: x")
      assert lang == "en"
    end

    test "unknown language is an error pointing at the header" do
      assert {:error, {"Language not supported: no-such", 1, 1}} =
               Scanner.scan("# language: no-such\n")
    end
  end

  describe "step keyword extraction" do
    test "keeps the trailing space on the keyword and trims trailing text whitespace" do
      [step] = tokens("Given the thing  ")
      assert step.payload.keyword == "Given "
      assert step.payload.text == "the thing"
    end

    test "star bullet keyword" do
      [step] = tokens("* a bullet step")
      assert step.payload.keyword == "* "
      assert step.payload.text == "a bullet step"
    end
  end

  describe "table cells" do
    test "trims cells, records the value column, drops the trailing segment" do
      [row] = tokens("  |  foo |bar|")
      cells = row.payload.cells
      assert Enum.map(cells, & &1.value) == ["foo", "bar"]
      # "foo" starts at column 6 (1-indexed); "bar" right after the second bar (col 11).
      assert Enum.map(cells, & &1.column) == [6, 11]
    end

    test "an empty cell is preserved" do
      [row] = tokens("|foo||boz|")
      assert Enum.map(row.payload.cells, & &1.value) == ["foo", "", "boz"]
    end

    test "left-to-right escape resolution" do
      # \\n => backslash + n (NOT newline); \n => newline; \| => pipe.
      [row] = tokens("| a\\\\nb | c\\nd | e\\|f |")
      assert Enum.map(row.payload.cells, & &1.value) == ["a\\nb", "c\nd", "e|f"]
    end
  end

  describe "tags" do
    test "splits on whitespace and records each @ column" do
      [line] = tokens("  @a @b")
      assert Enum.map(line.payload.tags, &{&1.name, &1.column}) == [{"@a", 3}, {"@b", 6}]
    end

    test "splits joined tags on every @" do
      [line] = tokens("@a@b")
      assert Enum.map(line.payload.tags, &{&1.name, &1.column}) == [{"@a", 1}, {"@b", 3}]
    end

    test "a trailing #comment ends tag parsing; a # inside a tag is kept" do
      [line] = tokens("@keep#hash #a comment")
      assert Enum.map(line.payload.tags, & &1.name) == ["@keep#hash"]
    end
  end
end
