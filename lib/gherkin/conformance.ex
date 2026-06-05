defmodule Gherkin.Conformance do
  @moduledoc """
  The single public entry point the conformance harness drives, and the place the
  reference pipeline is wired end-to-end:

      Source text --(scanner+parser)--> AST --(pickles compiler)--> Pickles
                                          |                            |
                                          v                            v
                                    AST NDJSON                   Pickles NDJSON

  Today the scanner/parser/compiler don't exist yet, so the AST and pickle stages
  return `:not_implemented`. As each is built, this module starts returning real
  NDJSON and the conformance score rises with **no harness changes**.

  ## Plugging in the parser / pickles compiler

  The two pipeline seams are dispatched through a swappable backend so fan-out agents
  can wire their implementation **without editing this file**. The backend is any
  module implementing the `Gherkin.Pipeline` behaviour; configure it with:

      config :gherkin, :pipeline, MyParser.Pipeline

  It defaults to `Gherkin.Pipeline.NotImplemented`. Routing through config also keeps
  the type checker honest: this module is written against the full behaviour types
  (`{:ok, ...}` / `{:error, ...}`), not the stub's narrow `:not_implemented`.

  Each function takes a `uri` (embedded verbatim in the envelopes — the harness passes
  the upstream-relative uri so output matches the golden files) and the raw feature
  `data`.
  """

  alias Gherkin.Message

  @type ndjson :: String.t()
  @type result :: {:ok, ndjson()} | :not_implemented | {:error, term()}

  @default_pipeline Gherkin.Pipeline.NotImplemented

  @doc "The configured pipeline backend (defaults to `Gherkin.Pipeline.NotImplemented`)."
  @spec pipeline() :: module()
  def pipeline, do: Application.get_env(:gherkin, :pipeline, @default_pipeline)

  # Parse through the configured backend, routing `.feature.md` uris to the Markdown
  # dialect via the optional `parse/3` callback (falling back to plain `parse/2` for
  # backends that do not implement it, e.g. the not-implemented stub).
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
  Produce the `Source` envelope NDJSON for a feature. Fully implemented.

  `format` is `:plain` (default) or `:markdown` for `.feature.md` inputs.
  """
  @spec source_ndjson(String.t(), String.t(), :plain | :markdown) :: {:ok, ndjson()}
  def source_ndjson(uri, data, format \\ :plain) do
    {:ok, Message.source_envelope(uri, data, format) |> Message.to_ndjson()}
  end

  @doc """
  Produce the `GherkinDocument` (AST) envelope NDJSON for a feature.

  Returns `:not_implemented` until a parser backend is configured.
  """
  @spec ast_ndjson(String.t(), String.t()) :: result()
  def ast_ndjson(uri, data) do
    case parse(uri, data) do
      {:ok, document} ->
        case Message.gherkin_document_envelope(document) do
          :not_implemented -> :not_implemented
          envelope -> {:ok, Message.to_ndjson(envelope)}
        end

      :not_implemented ->
        :not_implemented

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Produce the `Pickle` envelopes NDJSON for a feature (one line per pickle).

  Returns `:not_implemented` until a parser + pickles compiler backend is configured.
  """
  @spec pickles_ndjson(String.t(), String.t()) :: result()
  def pickles_ndjson(uri, data) do
    backend = pipeline()

    case parse(uri, data) do
      {:ok, document} ->
        case backend.compile_pickles(document) do
          :not_implemented ->
            :not_implemented

          pickles when is_list(pickles) ->
            envelopes = Enum.map(pickles, &Message.pickle_envelope/1)

            if Enum.any?(envelopes, &(&1 == :not_implemented)) do
              :not_implemented
            else
              {:ok, Message.to_ndjson(envelopes)}
            end
        end

      :not_implemented ->
        :not_implemented

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Produce the `parseError` envelope NDJSON for a malformed feature (bad-path).

  Returns `:not_implemented` until a parser backend surfaces structured errors.
  """
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

      _ ->
        :not_implemented
    end
  end
end
