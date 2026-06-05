# Vendored conformance corpus

The files under `test/conformance/testdata/` and `priv/gherkin-languages.json` are
vendored **verbatim** from the official Cucumber Gherkin reference implementation.

- Upstream repo: https://github.com/cucumber/gherkin
- Upstream commit: `374bc7a8f308a02d9ad1b45e02e8a3189c99f5dc`
- Vendored on: 2026-06-05

## What was copied

| Source (upstream)                | Destination (this repo)                      |
|----------------------------------|----------------------------------------------|
| `testdata/good/`                 | `test/conformance/testdata/good/`            |
| `testdata/bad/`                  | `test/conformance/testdata/bad/`             |
| `gherkin-languages.json`         | `priv/gherkin-languages.json`                |

## Corpus contents

- `testdata/good/` — 46 `*.feature` files, each accompanied by the golden outputs:
  - `*.feature.source.ndjson`   — the `Source` cucumber-message envelope
  - `*.feature.ast.ndjson`      — the `GherkinDocument` envelope (the AST)
  - `*.feature.pickles.ndjson`  — one `Pickle` envelope per runnable scenario/row
  - `*.feature.tokens`          — the scanner token dump (human-readable)
  - Some features also have a Markdown twin (`*.feature.md` + its `.md.*` goldens).
- `testdata/bad/` — 11 malformed `*.feature` files, each with a golden
  `*.feature.errors.ndjson` (`parseError` envelopes).

## Important: golden `uri` values

The golden NDJSON embeds `"uri":"../testdata/good/<name>.feature"` — paths relative to
the upstream test layout, **not** this repo's layout. The conformance harness normalizes
URIs on both sides before comparing (see `test/conformance/conformance_test.exs`).

## Re-vendoring

Do **not** hand-edit any of these files. To update, re-clone upstream at a newer commit
and re-copy, then bump the commit SHA above.

```sh
git clone --depth 1 https://github.com/cucumber/gherkin /tmp/cucumber-gherkin
cp -R /tmp/cucumber-gherkin/testdata/good test/conformance/testdata/good
cp -R /tmp/cucumber-gherkin/testdata/bad  test/conformance/testdata/bad
cp /tmp/cucumber-gherkin/gherkin-languages.json priv/gherkin-languages.json
git -C /tmp/cucumber-gherkin rev-parse HEAD   # record this SHA above
```
