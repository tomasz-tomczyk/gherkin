defmodule Gherkin.Location do
  @moduledoc """
  A 1-indexed source position attached to every AST node.

  Mirrors the cucumber-messages `Location` shape: `{line, column}`. Both are
  1-indexed. `column` may be `nil` in a handful of error envelopes (e.g. an
  "unexpected end of file" points only at a line), so it is allowed to be nil
  here and is omitted from JSON when nil — matching the reference serializer.
  """

  @type t :: %__MODULE__{line: pos_integer(), column: pos_integer() | nil}

  defstruct line: 0, column: nil

  @doc "Build a location from a line and optional column."
  @spec new(pos_integer(), pos_integer() | nil) :: t()
  def new(line, column \\ nil), do: %__MODULE__{line: line, column: column}
end
