defmodule Gherkin do
  @moduledoc """
  Public API for parsing Gherkin `.feature` documents and compiling them to pickles.

  This is the stable surface for downstream tools (e.g. a Cucumber runner). It is
  backed by the cucumber-messages-conformant `Gherkin.AstParser` pipeline:

      Source text --(parse)--> %Gherkin.AST.GherkinDocument{} --(pickles)--> [%Gherkin.Pickle{}]

  ## Functions

    * `parse/2` / `parse!/2` — produce the AST (`%Gherkin.AST.GherkinDocument{}`).
    * `pickles/2` — produce fully-resolved `%Gherkin.Pickle{}` structs: outline rows
      expanded, background steps prepended, tags inherited and unioned, and
      `<placeholder>` substitution applied. A runner consumes pickles, never raw
      `.feature` syntax.

  ## Options

    * `:uri` — the source uri embedded in the document / pickles (default `""`).
    * `:pipeline` — override the backend module implementing `Gherkin.Pipeline`
      (default `Gherkin.AstParser.Pipeline`). Primarily for testing.

  The default backend is wired **directly**, not through `Application.get_env/2`:
  Mix does not load a dependency's `config/config.exs`, so a downstream app
  depending on `:gherkin` via git/hex would otherwise silently fall back to the
  stub backend. The optional `config :gherkin, :pipeline, ...` override is still
  honoured when present, but is never required.

  ## Legacy parser

  The original line-based parser (producing `Gherkin.Elements.*` structs) now lives
  in `Gherkin.Legacy` (`Gherkin.Legacy.parse/1`, `flatten/1`, `scenarios_for/1`).
  It is non-conformant and kept only for backwards compatibility.

  ## Examples

      iex> {:ok, doc} = Gherkin.parse("Feature: Hi\\n  Scenario: S\\n    Given a step\\n")
      iex> doc.feature.name
      "Hi"

      iex> [pickle] = Gherkin.pickles("Feature: Hi\\n  Scenario: S\\n    Given a step\\n")
      iex> {pickle.name, Enum.map(pickle.steps, & &1.text)}
      {"S", ["a step"]}
  """

  alias Gherkin.AST.GherkinDocument
  alias Gherkin.Pickle

  @default_pipeline Gherkin.AstParser.Pipeline

  @type parse_error :: {String.t(), Gherkin.Location.t()}
  @type opts :: [uri: String.t(), pipeline: module()]

  @doc """
  Parse feature `data` into `{:ok, %Gherkin.AST.GherkinDocument{}}` or
  `{:error, errors}`, where `errors` is a list of `{message, %Gherkin.Location{}}`.

  See the module doc for options.
  """
  @spec parse(String.t(), opts()) ::
          {:ok, GherkinDocument.t()} | {:error, [parse_error()]}
  def parse(data, opts \\ []) when is_binary(data) do
    pipeline(opts).parse(uri(opts), data)
  end

  @doc """
  Like `parse/2`, but returns the `%Gherkin.AST.GherkinDocument{}` directly and
  raises `Gherkin.ParseError` on malformed input.
  """
  @spec parse!(String.t(), opts()) :: GherkinDocument.t()
  def parse!(data, opts \\ []) when is_binary(data) do
    case parse(data, opts) do
      {:ok, document} -> document
      {:error, errors} -> raise Gherkin.ParseError, errors: errors, uri: uri(opts)
    end
  end

  @doc """
  Parse `data` and compile it into a list of fully-resolved `%Gherkin.Pickle{}`.

  Raises `Gherkin.ParseError` on malformed input. Returns `[]` for a document with
  no feature (e.g. comments only).

  See the module doc for options and what "fully-resolved" means.
  """
  @spec pickles(String.t(), opts()) :: [Pickle.t()]
  def pickles(data, opts \\ []) when is_binary(data) do
    pipeline = pipeline(opts)
    pipeline.compile_pickles(parse!(data, opts))
  end

  defp pipeline(opts) do
    Keyword.get(opts, :pipeline) ||
      Application.get_env(:gherkin, :pipeline, @default_pipeline)
  end

  defp uri(opts), do: Keyword.get(opts, :uri, "")
end
