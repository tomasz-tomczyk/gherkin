defmodule Gherkin.AstParser.MarkdownScannerTest do
  @moduledoc """
  Unit tests for the Markdown-with-Gherkin (MDG) scanner. The scanner extracts a
  Gherkin token stream from a `.feature.md` source, which the existing
  recursive-descent parser then consumes unchanged. We assert on the classified
  token stream (type + key payload + location) so the rules from
  `MARKDOWN_WITH_GHERKIN.md` are pinned independently of the parser.
  """

  use ExUnit.Case, async: true

  alias Gherkin.AstParser.MarkdownScanner

  defp scan!(data) do
    {:ok, tokens, _lang} = MarkdownScanner.scan(data)
    tokens
  end

  defp types(tokens), do: Enum.map(tokens, & &1.type)

  # Scan a fragment as if it appeared inside a document whose Feature line is already
  # set, then return only the fragment's tokens. The first-significant-line Feature
  # fallback otherwise (correctly) claims the fragment's first line.
  defp scan_body!(body) do
    tokens = scan!("# Feature: F\n\n" <> body)
    # drop the feature line + the blank
    Enum.drop(tokens, 2)
  end

  defp body_types(body), do: scan_body!(body) |> types()

  describe "headers -> block keyword lines" do
    test "1-6 # levels map to Feature/Scenario/etc with correct column" do
      tokens =
        scan!("""
        ## Feature: DataTables

        ### Scenario: minimalistic
        """)

      [feature, _empty, scenario | _] = tokens
      assert feature.type == :feature_line
      assert feature.payload.keyword == "Feature"
      assert feature.payload.text == "DataTables"
      # column = indent + length("## ") + 1 = 0 + 3 + 1
      assert feature.column == 4

      assert scenario.type == :scenario_line
      assert scenario.payload.text == "minimalistic"
      assert scenario.column == 5
    end

    test "Scenario Outline header is recognised" do
      [outline] = scan!("## Scenario Outline: o") |> Enum.take(1)
      assert outline.type == :scenario_outline_line
      assert outline.payload.keyword == "Scenario Outline"
      assert outline.payload.text == "o"
    end
  end

  describe "bullets -> steps" do
    test "* / - / + bullet markers introduce steps; keyword type derived" do
      tokens = scan!("* Given a\n- When b\n+ Then c\n")
      assert types(tokens) == [:step_line, :step_line, :step_line]
      [g, w, t] = tokens
      assert {g.payload.keyword, g.payload.text} == {"Given ", "a"}
      assert {w.payload.keyword, w.payload.text} == {"When ", "b"}
      assert {t.payload.keyword, t.payload.text} == {"Then ", "c"}
      # `* Given a`: bullet prefix "* " (2) -> column 3
      assert g.column == 3
    end
  end

  describe "tables" do
    test "GFM rows indented 2-5 spaces are table rows; separator rows are skipped" do
      tokens =
        scan_body!("""
        * Given a simple data table
          | foo | bar |
          | --- | --- |
          | boz | boo |
        """)

      # The separator row `| --- |` is NOT a table row (it is neutered to :empty).
      assert types(tokens) == [:step_line, :table_row, :empty, :table_row]
      [_step, header, _sep, body] = tokens
      assert Enum.map(header.payload.cells, & &1.value) == ["foo", "bar"]
      assert Enum.map(body.payload.cells, & &1.value) == ["boz", "boo"]
    end

    test "an unindented GFM table is NOT a gherkin table (becomes empty)" do
      assert body_types("| foo | bar |\n") == [:empty]
    end
  end

  describe "doc strings (fenced code blocks)" do
    test "backtick fences open/close; inner shorter fence is body Other" do
      tokens =
        scan!("""
        * And a DocString
        ````
        ```
        ````
        """)

      assert types(tokens) == [
               :step_line,
               :doc_string_separator,
               :other,
               :doc_string_separator
             ]
    end
  end

  describe "tags (backtick-wrapped)" do
    test "backtick tags become a tag line with @-tag items and columns" do
      [tagline] = scan!("`@feature_tag1` `@feature_tag2`\n") |> Enum.take(1)
      assert tagline.type == :tag_line
      assert Enum.map(tagline.payload.tags, & &1.name) == ["@feature_tag1", "@feature_tag2"]
      [t1, t2] = tagline.payload.tags
      assert t1.column == 2
      assert t2.column == 18
    end
  end

  describe "non-gherkin prose is neutered to empty" do
    test "the first significant line becomes the feature line; prose is empty" do
      tokens =
        scan!("""
        Markdown document without "# Feature:" header
        ===========================================

        Lorem ipsum dolor sit amet.

        # Scenario: math
        * Given step one
        """)

      [feature | rest] = tokens
      assert feature.type == :feature_line
      assert feature.payload.text == ~s(Markdown document without "# Feature:" header)
      assert feature.column == 1

      # Everything up to the scenario header is prose -> :empty.
      scenario_idx = Enum.find_index(rest, &(&1.type == :scenario_line))
      assert Enum.all?(Enum.take(rest, scenario_idx), &(&1.type == :empty))
    end

    test "a non-keyword # header after the feature is also neutered" do
      tokens =
        scan!("""
        # Feature: F

        # The world is wet
        """)

      assert [%{type: :feature_line}, %{type: :empty}, %{type: :empty}] = tokens
    end
  end
end
