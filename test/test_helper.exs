# Conformance tests are tagged :pending until the parser/serializer pipeline is
# built out. They are excluded from the default `mix test` run so the suite stays
# green, but `mix test --only conformance` (or the `mix conformance` alias) runs
# them and prints the scoreboard. `--only conformance` re-includes them because an
# explicit `--only` overrides the `:pending` exclusion for matching tests.
ExUnit.start(exclude: [:pending])
