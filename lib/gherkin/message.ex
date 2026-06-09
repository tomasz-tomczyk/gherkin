defmodule Gherkin.Message do
  @moduledoc """
  cucumber-messages envelopes and their NDJSON serialization.

  The reference toolchain emits a stream of newline-delimited JSON envelopes. For the
  parser we care about three envelope kinds:

    * `Source`          — the raw `.feature` text + its media type + uri
    * `GherkinDocument` — the AST (`Gherkin.AST.GherkinDocument`)
    * `Pickle`          — one runnable scenario (`Gherkin.Pickle`)

  ## Key ordering

  The upstream golden NDJSON serializes object keys **alphabetically**. `to_ndjson/1`
  reproduces that with a recursive key-sort so output can be compared byte-for-byte
  after URI normalization. `nil` values are dropped (the reference omits absent
  optional fields rather than emitting `null`).
  """

  @media_type_plain "text/x.cucumber.gherkin+plain"
  @media_type_markdown "text/x.cucumber.gherkin+markdown"

  @type envelope :: map()

  @doc "The plain-Gherkin source media type."
  @spec media_type_plain() :: String.t()
  def media_type_plain, do: @media_type_plain

  @doc "The Markdown-with-Gherkin source media type."
  @spec media_type_markdown() :: String.t()
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
  Build a `GherkinDocument` envelope from a `Gherkin.AST.GherkinDocument`
  (projects via `Gherkin.Message.AST`).
  """
  @spec gherkin_document_envelope(Gherkin.AST.GherkinDocument.t()) :: envelope()
  def gherkin_document_envelope(%Gherkin.AST.GherkinDocument{} = doc) do
    %{"gherkinDocument" => Gherkin.Message.AST.document(doc)}
  end

  @doc """
  Build a `Pickle` envelope from a `Gherkin.Pickle` (projects via `Gherkin.Message.Pickle`).
  """
  @spec pickle_envelope(Gherkin.Pickle.t()) :: envelope()
  def pickle_envelope(%Gherkin.Pickle{} = pickle) do
    %{"pickle" => Gherkin.Message.Pickle.pickle(pickle)}
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
  one line per element.
  """
  @spec to_ndjson(envelope() | [envelope()]) :: String.t()
  def to_ndjson(envelopes) when is_list(envelopes) do
    Enum.map_join(envelopes, "", &(encode_sorted(&1) <> "\n"))
  end

  def to_ndjson(envelope) when is_map(envelope), do: encode_sorted(envelope) <> "\n"

  @doc false
  # Encode with recursively alphabetized keys to match the upstream golden byte layout.
  # The object/array structure is built explicitly (sorted) so key order is deterministic;
  # only scalar leaves are delegated to the built-in JSON encoder (Elixir 1.18+).
  @spec encode_sorted(term()) :: String.t()
  def encode_sorted(term), do: term |> encode_iodata() |> IO.iodata_to_binary()

  defp encode_iodata(map) when is_map(map) and not is_struct(map) do
    pairs =
      map
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map(fn {k, v} -> [JSON.encode!(k), ?:, encode_iodata(v)] end)

    [?{, Enum.intersperse(pairs, ?,), ?}]
  end

  defp encode_iodata(list) when is_list(list) do
    [?[, list |> Enum.map(&encode_iodata/1) |> Enum.intersperse(?,), ?]]
  end

  defp encode_iodata(other), do: JSON.encode!(other)

  @doc false
  # Shared by the AST and Pickle serializers: project a `Location` (or nil) into the
  # messages `{"line", "column"}` map. `column` is dropped when nil; a nil location
  # yields nil (pickle steps/arguments have no location) and is stripped by `to_ndjson`.
  @spec location_map(Gherkin.Location.t() | nil) :: map() | nil
  def location_map(nil), do: nil
  def location_map(%Gherkin.Location{line: line, column: nil}), do: %{"line" => line}

  def location_map(%Gherkin.Location{line: line, column: column}),
    do: %{"line" => line, "column" => column}

  @doc false
  # Shared by the serializers: insert `key` only when `value` is non-nil, so an absent
  # optional child never becomes an empty object rather than relying solely on the
  # recursive nil-drop in `to_ndjson`.
  @spec put_optional(map(), String.t(), term()) :: map()
  def put_optional(map, _key, nil), do: map
  def put_optional(map, key, value), do: Map.put(map, key, value)
end
