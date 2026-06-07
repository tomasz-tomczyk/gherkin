# Gherkin

[![CI](https://github.com/tomasz-tomczyk/gherkin/actions/workflows/ci.yml/badge.svg)](https://github.com/tomasz-tomczyk/gherkin/actions/workflows/ci.yml)

A **spec-conformant** Gherkin (`.feature`) parser for Elixir.

It parses Cucumber `.feature` source into a cucumber-messages `GherkinDocument`
AST and compiles it into runnable **pickles** — the same two-stage pipeline the
reference Cucumber implementations use:

```text
source text --(parse)--> %Gherkin.AST.GherkinDocument{} --(pickles)--> [%Gherkin.Pickle{}]
```

## Conformance

Validated against the official [`cucumber/gherkin`](https://github.com/cucumber/gherkin)
`testdata` corpus, byte-for-byte against the upstream golden NDJSON (after key
sorting + URI normalization):

| Area                    | Score  |
| ----------------------- | ------ |
| AST                     | 46/46  |
| Pickles                 | 46/46  |
| Errors (bad input)      | 11/11  |
| Markdown AST            | 5/5    |
| Markdown Pickles        | 5/5    |

The conformance suite is a CI gate: it asserts 100% in every area and fails the
build on any regression. Run it locally with:

```sh
mix conformance      # alias for: mix test --only conformance
```

## Highlights

- **Spec-conformant** — full AST, pickle compilation, error reporting, and the
  Markdown-with-Gherkin (`.feature.md`) dialect, matched against the upstream corpus.
- **Zero runtime dependencies** — pure Elixir; the only dev dependency is `ex_doc`.
- **Built-in JSON** — uses Elixir 1.18+'s built-in `JSON` module, no `jason`.
- **80 dialects** — the i18n keyword data is vendored and loaded once into
  `:persistent_term`.

## Requirements

- Elixir `~> 1.18` (built and tested on 1.18, 1.19, and 1.20)
- Erlang/OTP 27+

## Installation

Add `:gherkin` to your deps:

```elixir
def deps do
  [{:gherkin, "~> 3.0"}]
end
```

## Usage

### Parse to an AST

```elixir
{:ok, doc} = Gherkin.parse("Feature: Hi\n  Scenario: S\n    Given a step\n")
doc.feature.name
#=> "Hi"
```

`parse/2` returns `{:ok, %Gherkin.AST.GherkinDocument{}}` or `{:error, errors}`,
where each error is a `{message, %Gherkin.Location{}}` tuple. Use `parse!/2` to
get the document directly and raise `Gherkin.ParseError` on malformed input.

### Compile to pickles

A runner consumes pickles, never raw `.feature` syntax. `pickles/2` expands
scenario-outline rows, prepends background steps, unions inherited tags, and
substitutes `<placeholder>` values:

```elixir
[pickle] = Gherkin.pickles("Feature: Hi\n  Scenario: S\n    Given a step\n")
{pickle.name, Enum.map(pickle.steps, & &1.text)}
#=> {"S", ["a step"]}
```

### Options

- `:uri` — the source uri embedded in the document / pickles (default `""`).
- `:markdown` — parse the source as the Markdown-with-Gherkin dialect
  (`.feature.md`). Defaults to auto-detection: a `:uri` ending in `.md` is parsed
  as Markdown.

## Attribution

This is a fork of [`cabbage-ex/gherkin`](https://github.com/cabbage-ex/gherkin),
modernized for current Elixir and brought to full upstream conformance. The
original parser was extracted from
[white-bread](https://github.com/meadsteve/white-bread).

Original authors: Matt Widmann, Steve B, and Max Marcon.

## License

MIT. See [LICENSE](LICENSE).
