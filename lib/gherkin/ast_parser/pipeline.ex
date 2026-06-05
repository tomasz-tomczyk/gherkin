defmodule Gherkin.AstParser.Pipeline do
  @moduledoc """
  `Gherkin.Pipeline` backend wiring the new recursive-descent parser into the
  conformance harness and public API.

  `parse/2` delegates to `Gherkin.AstParser`; `compile_pickles/1` delegates to
  `Gherkin.AstParser.PickleCompiler`.

  Enable it with:

      config :gherkin, :pipeline, Gherkin.AstParser.Pipeline
  """

  @behaviour Gherkin.Pipeline

  @impl true
  def parse(uri, data), do: Gherkin.AstParser.parse(uri, data)

  @impl true
  def parse(uri, data, format), do: Gherkin.AstParser.parse(uri, data, format)

  @impl true
  def compile_pickles(document), do: Gherkin.AstParser.PickleCompiler.compile(document)
end
