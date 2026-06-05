# Architecture

This document describes the module layout of the Gherkin parser: how raw `.feature`
(and `.feature.md`) text becomes an AST and then runnable pickles, and how that output is
proven correct against the upstream `cucumber/gherkin` corpus.

The objective definition of "done" is binary and external: pass the upstream
`cucumber/gherkin` `testdata` corpus (see `test/conformance/UPSTREAM.md`). The conformance
harness (`mix conformance`) prints a scoreboard and hard-fails on any regression.

## The pipeline

```
.feature / .feature.md text
   │
   ▼   ┌──────────────────────────── Gherkin (this repo) ───────────────────────────┐
 Source → Scanner ──→ Tokens → Parser ──→ AST ──→ Id assigner ──→ Pickles compiler   │
   │      (dialect i18n)        (recursive descent)                (flatten/expand)   │
   └──────────────────────────────────────┬──────────────────────────┬──────────────┘
                                           │                          │
                                           ▼                          ▼
                                 GherkinDocument map            Pickle maps
                                           │                          │
                                           └──────── Message.to_ndjson ┘
                                                   (alphabetical key-sort, nil-drop)
                                                            │
                                                            ▼
                                                  AST / Pickles NDJSON
```

- **AST** = a faithful structure of the source (outlines, backgrounds, tables-as-templates
  preserved). Every node carries a 1-indexed `Location{line, column}` and a string `id`.
- **Pickle** = one concrete runnable scenario: outline rows expanded, background steps
  prepended, tags inherited/unioned, `<placeholder>` substitution applied.

The classic `.feature` and Markdown-with-Gherkin (`.feature.md`) formats share the *same*
parser, AST, and pickles compiler. Only the scanner (line classification) differs.

## Module layout

### Public API

| Module | File | Role |
|---|---|---|
| `Gherkin` | `lib/gherkin.ex` | The stable surface for downstream tools. `parse/2` / `parse!/2` produce the AST; `pickles/2` produces fully-resolved pickles. Defaults to the `Gherkin.AstParser.Pipeline` backend, wired **directly** (Mix does not load a dependency's `config/config.exs`); an alternative backend can be supplied via the `:pipeline` option or `config :gherkin, :pipeline, ...`. |
| `Gherkin.ParseError` | `lib/gherkin/parse_error.ex` | Raised by `parse!/2` and `pickles/2` on malformed input. |

### Parser pipeline (`Gherkin.AstParser.*`)

| Module | File | Role |
|---|---|---|
| `Gherkin.AstParser` | `lib/gherkin/ast_parser.ex` | Recursive-descent parser: token stream → `%Gherkin.AST.GherkinDocument{}` or `{:error, [{msg, %Location{}}]}`. Mirrors the reference grammar (feature / rule / background / scenario / scenario outline / examples / steps / tables / doc strings / tags) and collects multiple errors in source order. |
| `Gherkin.AstParser.Scanner` | `lib/gherkin/ast_parser/scanner.ex` | Classic `.feature` scanner: one `Token` per line, classified against a `Gherkin.Dialect` keyword set. |
| `Gherkin.AstParser.MarkdownScanner` | `lib/gherkin/ast_parser/markdown_scanner.ex` | Markdown-with-Gherkin (`.feature.md`) scanner; a port of the reference `GherkinInMarkdownTokenMatcher`. Emits the *same* token stream the classic scanner does, so the parser is shared. |
| `Gherkin.AstParser.Token` | `lib/gherkin/ast_parser/token.ex` | One scanned line: type, location, raw text, payload. |
| `Gherkin.AstParser.IdAssigner` | `lib/gherkin/ast_parser/id_assigner.ex` | Assigns string ids to AST nodes in the exact order the reference cucumber `AstBuilder` does, so emitted ids match the golden NDJSON byte-for-byte. |
| `Gherkin.AstParser.PickleCompiler` | `lib/gherkin/ast_parser/pickle_compiler.ex` | Compiles an id-assigned document into `[%Gherkin.Pickle{}]`: outline expansion, background prepend, tag inheritance, placeholder substitution, keywordType resolution (with conjunction inheritance). |
| `Gherkin.AstParser.Pipeline` | `lib/gherkin/ast_parser/pipeline.ex` | The `Gherkin.Pipeline` backend wiring the above into the public API and conformance harness. |

### Data, i18n, and serialization

| Module | File | Role |
|---|---|---|
| `Gherkin.Dialect` | `lib/gherkin/dialect.ex` | i18n foundation. Loads `priv/gherkin-languages.json` (80 dialects), caches in `:persistent_term`, returns keyword sets per language/group. |
| `Gherkin.AST.*` | `lib/gherkin/ast.ex` | AST node structs mirroring the cucumber-messages `GherkinDocument` schema. `Feature`/`Rule` `children` is an ordered tagged-tuple list preserving source order. |
| `Gherkin.Pickle` / `Gherkin.PickleStep` (+ table/doc-string structs) | `lib/gherkin/pickle.ex`, `lib/gherkin/pickle_step.ex` | A compiled, runnable scenario and its steps. |
| `Gherkin.Location` | `lib/gherkin/location.ex` | `%{line, column}` struct (1-indexed; `column` optional). |
| `Gherkin.Message` | `lib/gherkin/message.ex` | cucumber-messages envelopes + NDJSON serializer. `to_ndjson/1` recursively alphabetizes keys and drops `nil`s to match the golden byte layout. |
| `Gherkin.Message.AST` / `Gherkin.Message.Pickle` | `lib/gherkin/message/*.ex` | Project AST / pickle structs into the cucumber-messages map shapes. |
| `Gherkin.Pipeline` (behaviour) | `lib/gherkin/pipeline.ex` | The contract a parser/compiler backend implements: `parse/2` (+ optional `parse/3`) and `compile_pickles/1`. Lets callers swap backends (primarily for testing). |
| `Gherkin.Conformance` | `lib/gherkin/conformance.ex` | The single entry point the conformance harness drives. `source_ndjson/3`, `ast_ndjson/2`, `pickles_ndjson/2`, `errors_ndjson/2`. Defaults to `Gherkin.AstParser.Pipeline`. |

## Conformance harness

- `test/conformance/conformance_test.exs` — tagged `:conformance` + `:pending` so it is excluded
  from the default `mix test`. For every `testdata/good/*.feature` it grades `ast_ndjson` and
  `pickles_ndjson` against the golden `.ast.ndjson` / `.pickles.ndjson`; for every
  `testdata/bad/*.feature` it grades `errors_ndjson` against `.errors.ndjson`. The `.feature.md`
  Markdown twins are graded the same way. Comparison is byte-exact after recursive key-sort +
  uri-basename normalization.
- `mix conformance` (alias for `mix test --only conformance`, with `preferred_envs` so it runs
  in the `:test` env from any shell) runs it, prints the scoreboard, and exits non-zero on any
  regression.
- `test/conformance/testdata/` — the upstream corpus, vendored verbatim (see `UPSTREAM.md` for the
  pinned commit SHA). Do not hand-edit; re-vendor from upstream.

Current baseline: AST 46/46, Pickles 46/46, Errors 11/11, plus Markdown AST 5/5 and Pickles 5/5.
