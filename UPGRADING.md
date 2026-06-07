# Upgrading from 2.0.0 to 3.0.0

3.0.0 is a near-total rewrite. The public API is `Gherkin.parse/2` (an AST) and
`Gherkin.pickles/2` (runnable pickles). The old `parse/1 |> flatten` flow,
`parse_file/1`, `scenarios_for/1`, and the entire `Gherkin.Elements.*` struct
tree are gone. Tags and table keys are now strings, and the library requires
Elixir `~> 1.18`.

## 1. Bump the dependency and Elixir

```elixir
# mix.exs
def deps do
  [{:gherkin, "~> 3.0"}]
end
```

3.0.0 requires Elixir `~> 1.18` (2.x supported `~> 1.3`). The `jason` runtime
dependency is gone — 3.0.0 has zero runtime dependencies.

## 2. Replace `parse/1 |> flatten` with `pickles/2`

In 2.x you parsed a feature and then flattened it into scenarios (expanding
outlines, prepending background steps) yourself:

```elixir
# 2.0.0
feature =
  "test/features/checkout.feature"
  |> File.read!()
  |> Gherkin.parse()

scenarios =
  feature
  |> Gherkin.flatten()
  |> Map.get(:scenarios)
# or: Gherkin.scenarios_for(feature, tags: [...])
```

In 3.0.0 the **pickle compiler** does all of that — outline expansion,
background-step prepending, tag inheritance/union, and `<placeholder>`
substitution. A runner consumes pickles, never raw feature structs:

```elixir
# 3.0.0
pickles =
  "test/features/checkout.feature"
  |> File.read!()
  |> Gherkin.pickles(uri: "test/features/checkout.feature")

# Each pickle is one runnable scenario / expanded example row:
for pickle <- pickles do
  IO.puts(pickle.name)                       # scenario name (outline rows resolved)
  Enum.map(pickle.steps, & &1.text)          # step text, placeholders substituted
  Enum.map(pickle.tags, & &1.name)           # ["@smoke", ...] — strings, with leading @
end
```

There is no `parse_file/1` — read the file yourself and pass `:uri` so the URI is
embedded in the document and pickles.

`pickles/2` raises `Gherkin.ParseError` on malformed input (it builds on
`parse!/2`). If you want to handle errors as values, call `parse/2` first:

```elixir
case Gherkin.parse(source, uri: "checkout.feature") do
  {:ok, doc} -> # %Gherkin.AST.GherkinDocument{}
  {:error, errors} -> # [{message, %Gherkin.Location{line: _, column: _}}, ...]
end
```

## 3. Struct field mapping

If you walked the parsed feature struct directly, the shapes have changed.
`parse/2` returns `{:ok, %Gherkin.AST.GherkinDocument{}}` wrapping the feature.

| 2.0.0 (`%Gherkin.Elements.*{}`)        | 3.0.0                                                                 |
| -------------------------------------- | --------------------------------------------------------------------- |
| `parse/1` → `%Gherkin.Elements.Feature{}` | `parse/2` → `{:ok, %Gherkin.AST.GherkinDocument{}}`; the feature is at `doc.feature` |
| `feature.name`                         | `doc.feature.name`                                                    |
| `feature.description`                  | `doc.feature.description`                                             |
| `feature.tags` (atoms, e.g. `:wip`)    | `doc.feature.tags` → `[%Gherkin.AST.Tag{name: "@wip"}]` (strings, with `@`) |
| `feature.scenarios`                    | `doc.feature.children` — ordered `[{:background | :rule | :scenario, node}]` |
| `feature.background`                   | a `{:background, %Gherkin.AST.Background{}}` entry in `children`        |
| `scenario.steps`                       | `scenario.steps` → `[%Gherkin.AST.Step{}]` (`keyword`, `keyword_type`, `text`) |
| `step.keyword` (`:given`/`:when`/...)  | `step.keyword` is the literal text (`"Given "`, trailing space kept)   |
| scenario outline `examples`            | `scenario.examples` → `[%Gherkin.AST.Examples{table_header:, table_body:}]` |
| data table keys/values as atoms        | `%Gherkin.AST.DataTable{rows: [%TableRow{cells: [%TableCell{value: "..."}]}]}` — all strings |

In most cases you should **not** walk the AST by hand — use `pickles/2` and work
with `%Gherkin.Pickle{}` / `%Gherkin.PickleStep{}` instead. Pickles are the
stable, runner-facing shape:

- `%Gherkin.Pickle{name, language, steps, tags, ast_node_ids, ...}`
- `%Gherkin.PickleStep{text, type, argument, ast_node_ids, ...}`

## 4. Tags and table keys are strings

Everywhere a tag or a table key/value was an atom in 2.x, it is now a string:

```elixir
# 2.0.0
scenario.tags        #=> [:wip, :smoke]

# 3.0.0
Enum.map(pickle.tags, & &1.name)   #=> ["@wip", "@smoke"]
```

The non-standard "valued tag" syntax (`@tag:value`) is no longer parsed; tags
follow the upstream Gherkin grammar.
