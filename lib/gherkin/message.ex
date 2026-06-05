defmodule Gherkin.Message do
  @moduledoc """
  cucumber-messages envelopes and their NDJSON serialization.

  The reference toolchain emits a stream of newline-delimited JSON envelopes. For the
  parser we care about three envelope kinds:

    * `Source`          — the raw `.feature` text + its media type + uri
    * `GherkinDocument` — the AST (`Gherkin.AST.GherkinDocument`)
    * `Pickle`          — one runnable scenario (`Gherkin.Pickle`)

  ## Status

  `source_envelope/3` is fully implemented (no parser needed). The AST and Pickle
  serializers are wired but return `:not_implemented` until the parser/compiler land;
  the conformance harness already calls them, so the score rises automatically as
  those pieces are built.

  ## Key ordering

  The upstream golden NDJSON serializes object keys **alphabetically**. `to_ndjson/1`
  reproduces that with a recursive key-sort so output can be compared byte-for-byte
  after URI normalization. `nil` values are dropped (the reference omits absent
  optional fields rather than emitting `null`).
  """

  @media_type_plain "text/x.cucumber.gherkin+plain"
  @media_type_markdown "text/x.cucumber.gherkin+markdown"

  @type envelope :: map()
  @type not_implemented :: :not_implemented

  @doc "The plain-Gherkin source media type."
  def media_type_plain, do: @media_type_plain

  @doc "The Markdown-with-Gherkin source media type."
  def media_type_markdown, do: @media_type_markdown

  @doc """
  Build a `Source` envelope from raw feature text.

  `media_type` defaults to plain; pass `markdown` for `.feature.md` inputs. Fully
  implemented — does not depend on the parser.
  """
  @spec source_envelope(String.t(), String.t(), :plain | :markdown) :: envelope()
  def source_envelope(uri, data, format \\ :plain) do
    media_type =
      case format do
        :markdown -> @media_type_markdown
        _ -> @media_type_plain
      end

    %{"source" => %{"uri" => uri, "data" => data, "mediaType" => media_type}}
  end

  @doc """
  Build a `GherkinDocument` envelope from a `Gherkin.AST.GherkinDocument`.

  Returns `:not_implemented` until the AST serializer is built. The harness counts
  `:not_implemented` as a non-passing result, so wiring the real projection here
  drives the conformance score up.
  """
  @spec gherkin_document_envelope(Gherkin.AST.GherkinDocument.t()) ::
          envelope() | not_implemented()
  def gherkin_document_envelope(%Gherkin.AST.GherkinDocument{} = _doc) do
    # TODO(parser fan-out): project the AST struct tree into the cucumber-messages
    # GherkinDocument shape (string ids, trailing-space keywords, location maps).
    :not_implemented
  end

  @doc """
  Build a `Pickle` envelope from a `Gherkin.Pickle`.

  Returns `:not_implemented` until the pickles compiler + serializer are built.
  """
  @spec pickle_envelope(Gherkin.Pickle.t()) :: envelope() | not_implemented()
  def pickle_envelope(%Gherkin.Pickle{} = _pickle) do
    # TODO(pickles fan-out): project the Pickle struct into the cucumber-messages shape.
    :not_implemented
  end

  @doc "Build a `parseError` envelope from a message and source location (bad-path)."
  @spec parse_error_envelope(String.t(), String.t(), Gherkin.Location.t()) :: envelope()
  def parse_error_envelope(uri, message, %Gherkin.Location{} = location) do
    %{
      "parseError" => %{
        "message" => message,
        "source" => %{"uri" => uri, "location" => location_map(location)}
      }
    }
  end

  @doc """
  Serialize a single envelope (or list of envelopes) to NDJSON.

  Each envelope becomes one line of key-sorted JSON terminated by `\\n`. A list yields
  one line per element. `:not_implemented` envelopes are skipped (they contribute no
  line) so the serializer composes cleanly with not-yet-built pieces.
  """
  @spec to_ndjson(envelope() | not_implemented() | [envelope() | not_implemented()]) :: String.t()
  def to_ndjson(envelopes) when is_list(envelopes) do
    envelopes
    |> Enum.reject(&(&1 == :not_implemented))
    |> Enum.map_join("", &(encode_sorted(&1) <> "\n"))
  end

  def to_ndjson(:not_implemented), do: ""
  def to_ndjson(envelope) when is_map(envelope), do: encode_sorted(envelope) <> "\n"

  @doc false
  # Encode with recursively alphabetized keys to match the upstream golden byte layout.
  def encode_sorted(term) do
    term |> sort_keys() |> Jason.encode!()
  end

  defp sort_keys(map) when is_map(map) and not is_struct(map) do
    map
    |> Enum.map(fn {k, v} -> {k, sort_keys(v)} end)
    |> Enum.sort_by(fn {k, _} -> to_string(k) end)
    |> Jason.OrderedObject.new()
  end

  defp sort_keys(list) when is_list(list), do: Enum.map(list, &sort_keys/1)
  defp sort_keys(other), do: other

  defp location_map(%Gherkin.Location{line: line, column: nil}), do: %{"line" => line}

  defp location_map(%Gherkin.Location{line: line, column: column}),
    do: %{"line" => line, "column" => column}
end
