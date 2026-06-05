defmodule Gherkin.Conformance do
  @moduledoc """
  The single public entry point the conformance harness drives. It wires the reference
  pipeline end-to-end:

      Source text --(scanner+parser)--> AST --(pickles compiler)--> Pickles
                                          |                            |
                                          v                            v
                                    AST NDJSON                   Pickles NDJSON

  The backend is `Gherkin.AstParser.Pipeline` by default. An alternative backend
  implementing the `Gherkin.Pipeline` behaviour can be configured with:

      config :gherkin, :pipeline, MyParser.Pipeline

  Each function takes a `uri` (embedded verbatim in the envelopes — the harness passes
  the upstream-relative uri so output matches the golden files) and the raw feature
  `data`.
  """

  alias Gherkin.Message

  @type ndjson :: String.t()
  @type result :: {:ok, ndjson()} | {:error, term()}

  @default_pipeline Gherkin.AstParser.Pipeline

  @doc "The configured pipeline backend (defaults to `Gherkin.AstParser.Pipeline`)."
  @spec pipeline() :: module()
  def pipeline, do: Application.get_env(:gherkin, :pipeline, @default_pipeline)

  # Parse through the configured backend, routing `.feature.md` uris to the Markdown
  # dialect via the optional `parse/3` callback (falling back to plain `parse/2` for
  # backends that do not implement it).
  defp parse(uri, data) do
    backend = pipeline()

    cond do
      String.ends_with?(uri, ".md") and function_exported?(backend, :parse, 3) ->
        backend.parse(uri, data, :markdown)

      true ->
        backend.parse(uri, data)
    end
  end

  @doc """
  Produce the `Source` envelope NDJSON for a feature.

  `format` is `:plain` (default) or `:markdown` for `.feature.md` inputs.
  """
  @spec source_ndjson(String.t(), String.t(), :plain | :markdown) :: {:ok, ndjson()}
  def source_ndjson(uri, data, format \\ :plain) do
    {:ok, Message.source_envelope(uri, data, format) |> Message.to_ndjson()}
  end

  @doc "Produce the `GherkinDocument` (AST) envelope NDJSON for a feature."
  @spec ast_ndjson(String.t(), String.t()) :: result()
  def ast_ndjson(uri, data) do
    case parse(uri, data) do
      {:ok, document} ->
        {:ok, document |> Message.gherkin_document_envelope() |> Message.to_ndjson()}

      {:error, _} = error ->
        error
    end
  end

  @doc "Produce the `Pickle` envelopes NDJSON for a feature (one line per pickle)."
  @spec pickles_ndjson(String.t(), String.t()) :: result()
  def pickles_ndjson(uri, data) do
    backend = pipeline()

    case parse(uri, data) do
      {:ok, document} ->
        {:ok,
         document
         |> backend.compile_pickles()
         |> Enum.map(&Message.pickle_envelope/1)
         |> Message.to_ndjson()}

      {:error, _} = error ->
        error
    end
  end

  @doc "Produce the `parseError` envelope NDJSON for a malformed feature (bad-path)."
  @spec errors_ndjson(String.t(), String.t()) :: result()
  def errors_ndjson(uri, data) do
    case parse(uri, data) do
      {:error, errors} when is_list(errors) ->
        {:ok,
         errors
         |> Enum.map(fn {message, location} ->
           Message.parse_error_envelope(uri, message, location)
         end)
         |> Message.to_ndjson()}

      {:ok, _document} ->
        {:ok, ""}
    end
  end
end
