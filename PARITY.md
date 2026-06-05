# Cucumber/Gherkin parity checklist

Definition of done for "100% parity" with the official reference implementation
(github.com/cucumber/gherkin, cucumber-expressions, tag-expressions, messages, cucumber-ruby).

`[G]` = this repo (gherkin parser).  `[C]` = the runner (cabbage repo).
`(core)` = essential.  `(nice)` = advanced / rarely used.

## Parser (Gherkin) — this repo
- [ ] [G](core) Feature + free-form description
- [ ] [G](core) Scenario / Example (synonyms)
- [ ] [G](core) Given/When/Then/And/But + `*` bullet steps
- [ ] [G](core) Background (+ description)
- [ ] [G](core) Scenario Outline / Scenario Template (synonyms) with `<param>` substitution
- [ ] [G](core) Examples / Scenarios (synonyms); multiple tables
- [ ] [G](core) Rule (Gherkin 6) (+ description)
- [ ] [G](core) Comments (`#`)
- [ ] [G](core) Tags (`@`) on all taggable elements
- [ ] [G](core) Tag inheritance Feature→Rule→Scenario/Outline→Examples (resolved onto pickles)
- [ ] [G](core) Data Tables (`|`) — string cell shape, NOT atom keys
- [ ] [G](core) Doc Strings `"""` with significant-indentation dedent
- [ ] [G](nice) Doc Strings backtick fence
- [ ] [G](core) Doc String content/media-type annotation captured
- [ ] [G](core) `# language:` header + dialect selection
- [ ] [G](core) gherkin-languages.json — all 80 dialects (vendored verbatim)
- [ ] [G](core) Scanner → Tokens → Parser → AST with 1-indexed Location{line,column}
- [ ] [G](core) AST → Pickles compiler (1 pickle / scenario + / Examples row; background prepended; tags merged)
- [ ] [G](core) NDJSON representation of AST and Pickles
- [ ] [G](core) cucumber-messages envelopes: Source, GherkinDocument, Pickle
- [ ] [G](core) Error reporting for malformed input (matches testdata/bad)
- [ ] [G](core) **PASS testdata/good (ast+pickles+tokens) + testdata/bad (errors)** ← objective gate

## Expressions / tag-expressions (shared libs; consumed by runner)
- [ ] [C](core) Cucumber Expressions: `{int}{float}{word}{string}{}` + optional `(s)` + alternation `a/b` + escaping
- [ ] [C](nice) Typed variants `{bigdecimal}{double}{biginteger}{byte}{short}{long}`
- [ ] [C](core) Custom parameter type registration
- [ ] [C](core) Regex step definitions (alternative)
- [ ] [C](core) Tag-expression evaluator: `and`/`or`/`not`/parens

## Runner (Cucumber) — cabbage repo
- [ ] [C](core) Before/After scenario hooks
- [ ] [C](core) BeforeAll/AfterAll global hooks
- [ ] [C](core) Tagged/conditional hooks
- [ ] [C](nice) BeforeStep/AfterStep hooks (invoke-around)
- [ ] [C](nice) Around hooks; explicit hook ordering
- [ ] [C](core) World/context; fresh per-scenario state isolation
- [ ] [C](core) Step results: passed/failed/undefined/pending/ambiguous/skipped
- [ ] [C](core) Skip-after-failure/undefined/pending semantics
- [ ] [C](core) Undefined-step snippet generation
- [ ] [C](core) `--tags` filtering (tag expressions); `--name`; `file:line`
- [ ] [C](core) DataTable helpers: raw/rows/hashes/rows_hash/transpose
- [ ] [C](nice) DataTable diff!/column_names/cell-type conversion
- [ ] [C](core) Doc-string content-type delivered to step
- [ ] [C](core) Runner-side type registration (data table / doc string / default transformers)
- [ ] [C](core) `pretty` formatter
- [ ] [C](core) `message` (NDJSON) formatter + runner envelopes (TestCase/TestStep*/TestRun*)
- [ ] [C](nice) `progress` / legacy `json` / `html` / `junit` / `rerun` / `usage` formatters
- [ ] [C](core) Attachments/embeddings (media type → Attachment envelopes)
- [ ] [C](nice) `--retry`; profiles (cucumber.yml/@profile); parallel execution
