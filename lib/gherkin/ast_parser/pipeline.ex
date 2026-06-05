defmodule Gherkin.AstParser.Pipeline do
  @moduledoc """
  `Gherkin.Pipeline` backend wiring the new recursive-descent parser into the
  conformance harness and public API.

  `parse/2` delegates to `Gherkin.AstParser`. `compile_pickles/1` is still a stub
  (`:not_implemented`) — the pickles compiler is the next wave; leaving it stubbed
  keeps the Pickles conformance column where it was while the AST + Errors columns
  climb.

  Enable it with:

      config :gherkin, :pipeline, Gherkin.AstParser.Pipeline
  """

  @behaviour Gherkin.Pipeline

  @impl true
  def parse(uri, data), do: Gherkin.AstParser.parse(uri, data)

  @impl true
  def compile_pickles(_document), do: :not_implemented
end
