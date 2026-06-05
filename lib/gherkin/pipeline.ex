defmodule Gherkin.Pipeline do
  @moduledoc """
  The behaviour a parser/pickles-compiler backend implements to plug into
  `Gherkin.Conformance` (and, ultimately, the public `Gherkin` API).

  This is the contract the fan-out work targets. Implement both callbacks, then point
  the app at it:

      config :gherkin, :pipeline, MyParser.Pipeline

  The default backend is `Gherkin.Pipeline.NotImplemented`, which returns
  `:not_implemented` for everything — so the conformance harness runs and scores 0
  until a real backend exists.
  """

  @doc """
  Parse feature `data` (with the given `uri`) into a `Gherkin.AST.GherkinDocument`.

  Returns:

    * `{:ok, %Gherkin.AST.GherkinDocument{}}` for well-formed input,
    * `{:error, [{message :: String.t(), %Gherkin.Location{}}]}` for malformed input,
    * `:not_implemented` while the backend is a stub.
  """
  @callback parse(uri :: String.t(), data :: String.t()) ::
              {:ok, Gherkin.AST.GherkinDocument.t()}
              | {:error, [{String.t(), Gherkin.Location.t()}]}
              | :not_implemented

  @doc """
  Like `parse/2`, but with an explicit source `format`: `:plain` for classic
  `.feature` source or `:markdown` for the Markdown-with-Gherkin (`.feature.md`)
  dialect.

  Optional: backends that do not implement it fall back to `parse/2` (plain).
  """
  @callback parse(uri :: String.t(), data :: String.t(), format :: :plain | :markdown) ::
              {:ok, Gherkin.AST.GherkinDocument.t()}
              | {:error, [{String.t(), Gherkin.Location.t()}]}
              | :not_implemented

  @optional_callbacks [parse: 3]

  @doc """
  Compile a parsed document into a list of `Gherkin.Pickle` (outlines expanded,
  background prepended, tags inherited, placeholders substituted).

  Returns the pickle list, or `:not_implemented` while the backend is a stub.
  """
  @callback compile_pickles(document :: Gherkin.AST.GherkinDocument.t()) ::
              [Gherkin.Pickle.t()] | :not_implemented
end

defmodule Gherkin.Pipeline.NotImplemented do
  @moduledoc """
  Default `Gherkin.Pipeline` backend. Every callback returns `:not_implemented`.

  Replace it via `config :gherkin, :pipeline, MyParser.Pipeline` once a real parser
  and pickles compiler exist.
  """

  @behaviour Gherkin.Pipeline

  @impl true
  def parse(_uri, _data), do: :not_implemented

  @impl true
  def parse(_uri, _data, _format), do: :not_implemented

  @impl true
  def compile_pickles(_document), do: :not_implemented
end
