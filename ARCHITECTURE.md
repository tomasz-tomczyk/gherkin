# Architecture

This document describes the module layout of the modernized Gherkin parser and, crucially,
**where the not-yet-built pieces (scanner, parser, pickles compiler, serializers) plug in**.
It is the shared spine that fan-out work builds against.

The objective definition of "done" is binary and external: pass the upstream
`cucumber/gherkin` `testdata` corpus (see `test/conformance/UPSTREAM.md`). The conformance
harness (`mix conformance`) prints a live scoreboard that rises automatically as each piece
below is implemented — no harness edits required.

## The reference pipeline

```
.feature text
   │
   ▼   ┌──────────────────────── GHERKIN package (this repo) ───────────────────────┐
 Source → Scanner → Tokens → Parser → AST → Pickles compiler → cucumber-messages     │
   │                 (dialect-driven i18n)        (flatten/expand/inherit)            │
   └────────────────────────────────────────────────────────────────────────────────┘
                                       │                          │
                                       ▼                          ▼
                                  AST NDJSON                 Pickles NDJSON
```

- **AST** = a faithful structure of the source (outlines, backgrounds, tables-as-templates
  preserved). Every node carries a 1-indexed `Location{line, column}`.
- **Pickle** = one concrete runnable scenario: outline rows expanded, background steps
  prepended, tags inherited/unioned, placeholders substituted.

## Module layout

### Implemented today (pure / data-driven — verifiable now)

| Module | File | Role |
|---|---|---|
| `Gherkin.Dialect` | `lib/gherkin/dialect.ex` | i18n foundation. Loads `priv/gherkin-languages.json` (80 dialects), caches in `:persistent_term`, returns keyword sets per language/group. Fully implemented + tested (`test/gherkin/dialect_test.exs`). |
| `Gherkin.Location` | `lib/gherkin/location.ex` | `%{line, column}` struct (1-indexed; `column` optional). Used on every AST node. |
| `Gherkin.Message` | `lib/gherkin/message.ex` | cucumber-messages envelopes + NDJSON serializer. `source_envelope/3`, `parse_error_envelope/3`, and `to_ndjson/1` (recursive alphabetical key-sort to match golden byte layout, `nil`-dropping) are done. `gherkin_document_envelope/1` and `pickle_envelope/1` are wired but return `:not_implemented`. |
| `Gherkin.Conformance` | `lib/gherkin/conformance.ex` | The single public entry point the harness drives. `source_ndjson/3` is done; `ast_ndjson/2`, `pickles_ndjson/2`, `errors_ndjson/2` dispatch through the configurable pipeline backend. |

### Type-only spine (structs/behaviour, no logic yet — the build target)

| Module | File | Role |
|---|---|---|
| `Gherkin.AST.*` | `lib/gherkin/ast.ex` | AST node structs mirroring the cucumber-messages `GherkinDocument` schema: `GherkinDocument`, `Feature`, `Rule`, `Background`, `Scenario` (also represents Scenario Outline), `Examples`, `Step`, `DataTable`, `TableRow`, `TableCell`, `DocString`, `Tag`, `Comment`. `Feature`/`Rule` `children` is an ordered tagged-tuple list (`{:background|:rule|:scenario, node}`) preserving source order. |
| `Gherkin.Pickle` (+ `Gherkin.Pickle.Tag`) | `lib/gherkin/pickle.ex` | A compiled, runnable scenario. |
| `Gherkin.PickleStep` (+ `Gherkin.Pickle.DataTable` / `Gherkin.Pickle.DocString`) | `lib/gherkin/pickle_step.ex` | A single pickle step + its optional argument. |
| `Gherkin.Pipeline` (behaviour) + `Gherkin.Pipeline.NotImplemented` (default) | `lib/gherkin/pipeline.ex` | The contract a parser/compiler backend implements: `parse/2` (text → AST or errors) and `compile_pickles/1` (AST → pickles). The default returns `:not_implemented` for everything. |

### Legacy (still serving the current public API)

`Gherkin.parse/1` and the `Gherkin.Elements.*` structs (`lib/gherkin/elements/*.ex`,
`lib/gherkin/parser.ex`, `lib/gherkin/parsers/*.ex`) are the original hand-written parser.
They stay green and untouched until the new pipeline fully replaces them. The new AST is
intentionally a **separate** namespace (`Gherkin.AST.*`) so the rewrite can land incrementally
without breaking existing callers.

## The plug-in seam (how fan-out work lands without editing the harness)

`Gherkin.Conformance` does not call a parser directly. It calls a **swappable backend**
resolved at runtime:

```elixir
def pipeline, do: Application.get_env(:gherkin, :pipeline, Gherkin.Pipeline.NotImplemented)
```

To wire a real implementation, point the config at a module implementing the
`Gherkin.Pipeline` behaviour:

```elixir
# config/config.exs
config :gherkin, :pipeline, MyParser.Pipeline
```

That single line is the only integration point. `Gherkin.Conformance` is written against the
**full** behaviour return types (`{:ok, doc}` / `{:error, [{msg, loc}]}` / `:not_implemented`),
so backends can return real results and the score climbs with no changes to the harness or the
conformance entry point.

### Two serializer seams remain inside `Gherkin.Message`

Even with a parsing backend wired, two `:not_implemented` projections must be filled to score:

- `Gherkin.Message.gherkin_document_envelope/1` — project a `%Gherkin.AST.GherkinDocument{}`
  into the cucumber-messages `GherkinDocument` map shape (string ids, trailing-space keywords,
  location maps). Drives the **AST** column.
- `Gherkin.Message.pickle_envelope/1` — project a `%Gherkin.Pickle{}` into the messages `Pickle`
  shape. Drives the **Pickles** column.

`to_ndjson/1` and `encode_sorted/1` (alphabetical key-sort, `nil`-drop) already handle byte-exact
golden matching, so these projections only need to produce the right maps — not worry about
serialization order.

## Conformance harness

- `test/conformance/conformance_test.exs` — tagged `:conformance` + `:pending` so it is excluded
  from the default `mix test` (kept green). For every `testdata/good/*.feature` it grades
  `ast_ndjson` and `pickles_ndjson` against the golden `.ast.ndjson` / `.pickles.ndjson`; for
  every `testdata/bad/*.feature` it grades `errors_ndjson` against `.errors.ndjson`. Comparison is
  byte-exact after recursive key-sort + uri-basename normalization. Each file grades to
  `:pass | :fail | :not_implemented | :error`, tallied into a printed scoreboard.
- `mix conformance` (alias for `mix test --only conformance`) runs it and prints:

  ```
  Conformance: AST p/N, Pickles q/N, Errors r/M
  ```

- `test/conformance/testdata/` — the upstream corpus, vendored verbatim (see `UPSTREAM.md` for the
  pinned commit SHA). Do not hand-edit; re-vendor from upstream.

## Where each fan-out work item plugs in

| Work item | Plug-in point | Score column it moves |
|---|---|---|
| **Scanner / tokenizer** | new module, consumed by the parser; classifies lines against `Gherkin.Dialect` keyword sets | (enables AST + Errors) |
| **AST parser** | `MyParser.Pipeline.parse/2` returning `{:ok, %Gherkin.AST.GherkinDocument{}}` / `{:error, [{msg, %Location{}}]}` | AST + Errors |
| **AST → messages serializer** | `Gherkin.Message.gherkin_document_envelope/1` | AST |
| **Pickles compiler** | `MyParser.Pipeline.compile_pickles/1` returning `[%Gherkin.Pickle{}]` | Pickles |
| **Pickle → messages serializer** | `Gherkin.Message.pickle_envelope/1` | Pickles |
| **Error recovery / bad path** | parser's `{:error, [...]}` return + `Gherkin.Message.parse_error_envelope/3` (already done) | Errors |
