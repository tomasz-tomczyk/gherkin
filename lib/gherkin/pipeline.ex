defmodule Gherkin.Pipeline do
  @moduledoc """
  The behaviour a parser/pickles-compiler backend implements to plug into
  `Gherkin.Conformance` and the public `Gherkin` API.

  The shipped backend is `Gherkin.AstParser.Pipeline` (the recursive-descent parser +
  pickles compiler). It is the default everywhere; this behaviour exists so callers can
  swap in an alternative implementation (primarily for testing) via the `:pipeline`
  option on the public API, or `config :gherkin, :pipeline, MyParser.Pipeline`.
  """

  @doc """
  Parse feature `data` (with the given `uri`) into a `Gherkin.AST.GherkinDocument`.

  Returns:

    * `{:ok, %Gherkin.AST.GherkinDocument{}}` for well-formed input,
    * `{:error, [{message :: String.t(), %Gherkin.Location{}}]}` for malformed input.
  """
  @callback parse(uri :: String.t(), data :: String.t()) ::
              {:ok, Gherkin.AST.GherkinDocument.t()}
              | {:error, [{String.t(), Gherkin.Location.t()}]}

  @doc """
  Like `parse/2`, but with an explicit source `format`: `:plain` for classic
  `.feature` source or `:markdown` for the Markdown-with-Gherkin (`.feature.md`)
  dialect.

  Optional: backends that do not implement it fall back to `parse/2` (plain).
  """
  @callback parse(uri :: String.t(), data :: String.t(), format :: :plain | :markdown) ::
              {:ok, Gherkin.AST.GherkinDocument.t()}
              | {:error, [{String.t(), Gherkin.Location.t()}]}

  @optional_callbacks [parse: 3]

  @doc """
  Compile a parsed document into a list of `Gherkin.Pickle` (outlines expanded,
  background prepended, tags inherited, placeholders substituted).
  """
  @callback compile_pickles(document :: Gherkin.AST.GherkinDocument.t()) ::
              [Gherkin.Pickle.t()]
end
