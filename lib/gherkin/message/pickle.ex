defmodule Gherkin.Message.Pickle do
  @moduledoc """
  Projects a `Gherkin.Pickle` struct into the cucumber-messages `Pickle` map shape
  consumed by `Gherkin.Message.to_ndjson/1`.

  This is the pickle serializer seam from `ARCHITECTURE.md`. Like `Gherkin.Message.AST`
  it is a mechanical snake_case -> camelCase projection; `to_ndjson` handles the
  alphabetical key-sort and recursive nil-drop, so this module only assembles maps.

  Shape notes that match the goldens:

    * a pickle carries `astNodeIds`, `id`, `language`, `location`, `name`, `steps`,
      `tags`, `uri`;
    * a pickle step carries `astNodeIds`, `id`, `text`, `type`, and an optional
      `argument`;
    * a pickle-step `dataTable` has rows of `cells` where each cell is just
      `{"value" => ...}` — no id, no location;
    * a pickle-step `docString` has only `content` and an optional `mediaType` —
      no location, no delimiter;
    * a pickle tag is `{"astNodeId" => ..., "name" => ...}`.
  """

  alias Gherkin.{Pickle, PickleStep}

  @doc "Project a `Gherkin.Pickle` struct into the messages map."
  @spec pickle(Pickle.t()) :: map()
  def pickle(%Pickle{} = p) do
    %{
      "id" => p.id,
      "uri" => p.uri,
      "name" => p.name,
      "language" => p.language,
      "location" => location(p.location),
      "steps" => Enum.map(p.steps, &step/1),
      "tags" => Enum.map(p.tags, &tag/1),
      "astNodeIds" => p.ast_node_ids
    }
  end

  defp step(%PickleStep{} = s) do
    %{
      "id" => s.id,
      "text" => s.text,
      "type" => s.type,
      "astNodeIds" => s.ast_node_ids
    }
    |> put_optional("argument", argument(s.argument))
  end

  defp argument(nil), do: nil

  defp argument({:data_table, %Pickle.DataTable{rows: rows}}) do
    %{"dataTable" => %{"rows" => Enum.map(rows, &data_table_row/1)}}
  end

  defp argument({:doc_string, %Pickle.DocString{} = ds}) do
    doc =
      %{"content" => ds.content}
      |> put_optional("mediaType", ds.media_type)

    %{"docString" => doc}
  end

  defp data_table_row(cells) do
    %{"cells" => Enum.map(cells, fn value -> %{"value" => value} end)}
  end

  defp tag(%Pickle.Tag{} = t) do
    %{"name" => t.name, "astNodeId" => t.ast_node_id}
  end

  defp location(nil), do: nil

  defp location(%Gherkin.Location{line: line, column: nil}), do: %{"line" => line}

  defp location(%Gherkin.Location{line: line, column: column}),
    do: %{"line" => line, "column" => column}

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)
end
