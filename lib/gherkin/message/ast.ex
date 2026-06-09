defmodule Gherkin.Message.AST do
  @moduledoc """
  Projects a `Gherkin.AST.GherkinDocument` struct tree into the cucumber-messages
  `GherkinDocument` map shape consumed by `Gherkin.Message.to_ndjson/1`.

  It is a mechanical snake_case -> camelCase projection that:

    * emits `location` maps (`column` dropped when nil — handled by `to_ndjson`),
    * keeps trailing-space step keywords as-is,
    * preserves empty collections (`tags: []`, `examples: []`, `comments: []`,
      `children: []`) which the reference emits rather than omitting,
    * drops nil optionals (`mediaType`, `dataTable`/`docString` on steps, `id` when
      unassigned) — `to_ndjson` strips nils recursively.

  Note the asymmetries that match the goldens: a `Background` has no `tags` key; a
  `DataTable` has no `id`; a `TableCell` has no `id`; the feature node itself has no
  `id` (only its descendants and tags do).
  """

  alias Gherkin.AST.{
    Background,
    Comment,
    DataTable,
    DocString,
    Examples,
    Feature,
    GherkinDocument,
    Rule,
    Scenario,
    Step,
    TableCell,
    TableRow,
    Tag
  }

  @doc "Project a `GherkinDocument` struct into the messages map."
  @spec document(GherkinDocument.t()) :: map()
  def document(%GherkinDocument{} = doc) do
    %{
      "uri" => doc.uri,
      "comments" => Enum.map(doc.comments, &comment/1)
    }
    |> put_optional("feature", doc.feature && feature(doc.feature))
  end

  defp feature(%Feature{} = f) do
    %{
      "location" => location(f.location),
      "language" => f.language,
      "name" => f.name,
      "description" => f.description,
      "tags" => Enum.map(f.tags, &tag/1),
      "children" => Enum.map(f.children, &child/1)
    }
    # A Markdown feature with no `# Feature:` header has no keyword; the reference
    # omits the field entirely (rather than emitting null) in that case.
    |> put_optional("keyword", f.keyword)
  end

  defp child({:background, bg}), do: %{"background" => background(bg)}
  defp child({:scenario, sc}), do: %{"scenario" => scenario(sc)}
  defp child({:rule, rule}), do: %{"rule" => rule(rule)}

  defp rule(%Rule{} = r) do
    %{
      "id" => r.id,
      "location" => location(r.location),
      "keyword" => r.keyword,
      "name" => r.name,
      "description" => r.description,
      "tags" => Enum.map(r.tags, &tag/1),
      "children" => Enum.map(r.children, &rule_child/1)
    }
  end

  defp rule_child({:background, bg}), do: %{"background" => background(bg)}
  defp rule_child({:scenario, sc}), do: %{"scenario" => scenario(sc)}

  defp background(%Background{} = bg) do
    %{
      "id" => bg.id,
      "location" => location(bg.location),
      "keyword" => bg.keyword,
      "name" => bg.name,
      "description" => bg.description,
      "steps" => Enum.map(bg.steps, &step/1)
    }
  end

  defp scenario(%Scenario{} = sc) do
    %{
      "id" => sc.id,
      "location" => location(sc.location),
      "keyword" => sc.keyword,
      "name" => sc.name,
      "description" => sc.description,
      "tags" => Enum.map(sc.tags, &tag/1),
      "steps" => Enum.map(sc.steps, &step/1),
      "examples" => Enum.map(sc.examples, &examples/1)
    }
  end

  defp examples(%Examples{} = ex) do
    %{
      "id" => ex.id,
      "location" => location(ex.location),
      "keyword" => ex.keyword,
      "name" => ex.name,
      "description" => ex.description,
      "tags" => Enum.map(ex.tags, &tag/1),
      "tableBody" => Enum.map(ex.table_body, &table_row/1)
    }
    |> put_optional("tableHeader", ex.table_header && table_row(ex.table_header))
  end

  defp step(%Step{} = s) do
    %{
      "id" => s.id,
      "location" => location(s.location),
      "keyword" => s.keyword,
      "keywordType" => s.keyword_type,
      "text" => s.text
    }
    |> put_optional("dataTable", s.data_table && data_table(s.data_table))
    |> put_optional("docString", s.doc_string && doc_string(s.doc_string))
  end

  defp data_table(%DataTable{} = dt) do
    %{
      "location" => location(dt.location),
      "rows" => Enum.map(dt.rows, &table_row/1)
    }
  end

  defp doc_string(%DocString{} = ds) do
    %{
      "location" => location(ds.location),
      "content" => ds.content,
      "delimiter" => ds.delimiter
    }
    |> put_optional("mediaType", ds.media_type)
  end

  defp table_row(%TableRow{} = row) do
    %{
      "id" => row.id,
      "location" => location(row.location),
      "cells" => Enum.map(row.cells, &table_cell/1)
    }
  end

  defp table_cell(%TableCell{} = c) do
    %{"location" => location(c.location), "value" => c.value}
  end

  defp tag(%Tag{} = t) do
    %{"id" => t.id, "location" => location(t.location), "name" => t.name}
  end

  defp comment(%Comment{} = c) do
    %{"location" => location(c.location), "text" => c.text}
  end

  defp location(%Gherkin.Location{line: line, column: nil}), do: %{"line" => line}

  defp location(%Gherkin.Location{line: line, column: column}),
    do: %{"line" => line, "column" => column}

  # `to_ndjson` drops nils recursively, but we avoid even inserting keys whose value
  # is a nil sub-tree (mediaType, optional feature, dataTable/docString) so the shape
  # is obvious and we never emit an empty object for an absent child.
  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)
end
