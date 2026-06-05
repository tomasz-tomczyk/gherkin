defmodule Gherkin.AstParser.LineUtil do
  @moduledoc false
  # Pure line-handling helpers shared byte-for-byte by both scanners
  # (`Gherkin.AstParser.Scanner` and `Gherkin.AstParser.MarkdownScanner`). Splitting
  # them out keeps the two scanners from drifting apart on line splitting / indentation.

  @doc """
  Split `data` into lines, stripping a single trailing `\\r` per line (CRLF support).
  A trailing newline does NOT create a spurious empty final line.
  """
  @spec split_lines(String.t()) :: [String.t()]
  def split_lines(data) do
    data
    |> String.split("\n")
    |> drop_trailing_empty()
    |> Enum.map(&String.replace_suffix(&1, "\r", ""))
  end

  @doc """
  Drop a single trailing empty element.

  `["a", "b", ""]` -> `["a", "b"]`, but `["a", "b"]` is unchanged. This is what makes a
  trailing newline in the source not produce a spurious empty final line.
  """
  @spec drop_trailing_empty([String.t()]) :: [String.t()]
  def drop_trailing_empty(parts) do
    case Enum.reverse(parts) do
      ["" | rest] -> Enum.reverse(rest)
      _ -> parts
    end
  end

  @doc "Count leading spaces/tabs on a line (the 0-indexed indentation width)."
  @spec leading_space_count(String.t()) :: non_neg_integer()
  def leading_space_count(line) do
    line
    |> String.graphemes()
    |> Enum.take_while(&(&1 == " " or &1 == "\t"))
    |> length()
  end
end
