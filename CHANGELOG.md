# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Fixed

- Markdown-with-Gherkin (`.feature.md`) documents now populate `feature.description`
  from a leading Markdown table that precedes the first heading, matching the
  reference parser and the CCK `markdown` sample (`feature.description` is
  `"| boz | boo |"` for that sample). The parser already produced the description;
  the conformance routing in `Gherkin.Conformance` used a bare `function_exported?/3`
  guard that returns `false` for a not-yet-loaded backend module, so the first
  `.feature.md` parse in a fresh VM silently fell back to the plain `.feature`
  scanner and emitted spurious parse errors. The router now pairs the check with
  `Code.ensure_loaded?/1`. The CCK `markdown` sample is vendored into the conformance
  corpus to pin this.

## 3.0.0 - 2026-06-05

A near-total rewrite. The 2.x line was a hand-maintained parser that produced a
bespoke `%Gherkin.Elements.Feature{}` struct. 3.0.0 replaces it with a
cucumber-messages-conformant pipeline that produces a `GherkinDocument` AST and
compiles it into runnable pickles, validated byte-for-byte against the official
`cucumber/gherkin` corpus.

This is shipped as a new major on the existing `gherkin` package (2.0.0 cannot be
overwritten, and the API surface is incompatible). See [UPGRADING.md](UPGRADING.md)
for a concrete 2.0.0 → 3.0.0 migration guide.

### Breaking

- `Gherkin.parse/1` is now `Gherkin.parse/2` and returns
  `{:ok, %Gherkin.AST.GherkinDocument{}}` / `{:error, errors}` instead of a bare
  `%Gherkin.Elements.Feature{}`. The document wraps a `feature`, comments, and
  `%Gherkin.Location{line, column}` on every node.
- Removed `Gherkin.parse_file/1`. Read the file yourself and pass the contents to
  `parse/2` (use the `:uri` option to embed the source path).
- Removed `Gherkin.flatten/1` and `Gherkin.scenarios_for/1`. Scenario-outline
  expansion, background-step prepending, and tag inheritance are now done by the
  pickle compiler — call `Gherkin.pickles/2` instead (see UPGRADING.md).
- Removed all of `Gherkin.Elements.*` (`Feature`, `Scenario`, `Step`, `Background`,
  `ScenarioOutline`, etc.), `Gherkin.Parser`, and `Gherkin.Parsers.*`. The AST now
  lives under `Gherkin.AST.*` and pickles under `Gherkin.Pickle` /
  `Gherkin.PickleStep`.
- Tags and data-table / examples-table keys are now **strings**, not atoms. Tag
  values such as `@wip` are represented as `"@wip"`.
- Removed support for the non-standard "valued" tag syntax (`@tag:value`). Tags
  follow the upstream Gherkin grammar — whitespace-separated `@`-prefixed names.
- Minimum Elixir is now `~> 1.18` (was `~> 1.3`).
- Removed the `jason` runtime dependency. Message/dialect serialization uses the
  built-in Elixir `JSON` module. The library now has **zero runtime dependencies**.

### Added

- A full cucumber-messages-conformant pipeline:
  scanner → parser → `GherkinDocument` AST (with `Location` on every node) →
  pickle compiler → NDJSON cucumber-message envelopes.
- `Gherkin.parse!/2` — raises `Gherkin.ParseError` on malformed input instead of
  returning an `{:error, _}` tuple.
- `Gherkin.pickles/2` — compiles a document into fully-resolved
  `%Gherkin.Pickle{}` structs: outline rows expanded, background steps prepended,
  tags inherited and unioned, and `<placeholder>` substitution applied. This is
  what a Cucumber runner consumes.
- Internationalization via `Gherkin.Dialect` — 80 dialects sourced from the
  official `gherkin-languages.json`, selectable with a `# language:` header.
- Markdown-with-Gherkin dialect support (`.feature.md`), auto-detected from a
  `.md` `:uri` or forced with the `:markdown` option.
- `Rule` support, and doc-string media types.
- The conformance scoreboard: `mix conformance` (alias for
  `mix test --only conformance`) reports per-axis pass counts and gates CI.

### Conformance

Validated against the official `cucumber/gherkin` corpus:

- AST: 46/46
- Pickles: 46/46
- Errors (bad input): 11/11
- Markdown (AST + Pickles): 5/5
