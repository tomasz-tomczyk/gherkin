defmodule Gherkin.ConformanceTest do
  @moduledoc """
  The objective parity scoreboard, run against the vendored upstream `testdata` corpus
  (see `test/conformance/UPSTREAM.md`).

  For every `testdata/good/*.feature` it asks `Gherkin.Conformance` to emit the AST and
  Pickle NDJSON and compares (after key-sorting + URI normalization) against the golden
  `*.ast.ndjson` / `*.pickles.ndjson`. For every `testdata/bad/*.feature` it compares the
  emitted `parseError` NDJSON against the golden `*.errors.ndjson`.

  Because the parser/serializer aren't built yet, the comparisons mostly resolve to
  `:not_implemented`. Rather than turning the suite red, the harness *counts* outcomes
  and PRINTS a baseline scoreboard, then asserts only that the harness itself ran. As
  the pipeline is implemented, the printed score rises automatically — no edits here.

  These tests are tagged `:conformance` and `:pending`, so they are excluded from the
  default `mix test` (see `test/test_helper.exs`). Run them with:

      mix conformance          # alias for `mix test --only conformance`
      mix test --only conformance
  """

  use ExUnit.Case, async: false

  @moduletag :conformance
  @moduletag :pending

  @testdata_dir Path.join(__DIR__, "testdata")
  @good_dir Path.join(@testdata_dir, "good")
  @bad_dir Path.join(@testdata_dir, "bad")

  # The golden NDJSON embeds upstream-relative uris like "../testdata/good/x.feature".
  # We rebuild that exact uri per file so emitted envelopes can match the goldens.
  defp upstream_uri(kind, basename), do: "../testdata/#{kind}/#{basename}"

  # Only plain `.feature` files (skip the Markdown `.feature.md` twins for now; they
  # share the same golden mechanics and can be folded in once the parser handles them).
  defp good_features do
    Path.wildcard(Path.join(@good_dir, "*.feature"))
    |> Enum.reject(&String.ends_with?(&1, ".md"))
    |> Enum.sort()
  end

  defp bad_features do
    Path.wildcard(Path.join(@bad_dir, "*.feature"))
    |> Enum.reject(&String.ends_with?(&1, ".md"))
    |> Enum.sort()
  end

  # Normalize an NDJSON blob to a canonical, comparable form: decode each line, sort
  # keys recursively, drop the uri's directory so a uri mismatch never masks a real
  # structural diff, and re-encode. Returns a list of canonical line strings.
  defp canonical_lines(ndjson) when is_binary(ndjson) do
    ndjson
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      line
      |> Jason.decode!()
      |> strip_uri()
      |> Gherkin.Message.encode_sorted()
    end)
  end

  # Replace any "uri" value with just its basename so repo-layout vs upstream-layout
  # path differences don't cause false negatives.
  defp strip_uri(%{} = map) do
    map
    |> Map.new(fn
      {"uri", v} when is_binary(v) -> {"uri", Path.basename(v)}
      {k, v} -> {k, strip_uri(v)}
    end)
  end

  defp strip_uri(list) when is_list(list), do: Enum.map(list, &strip_uri/1)
  defp strip_uri(other), do: other

  # Compare emitted NDJSON against a golden file. Returns :pass | :fail | :not_implemented
  # | :error so the scoreboard can break the result down honestly.
  defp grade(result, golden_path) do
    cond do
      result == :not_implemented ->
        :not_implemented

      match?({:error, _}, result) ->
        :error

      match?({:ok, _}, result) ->
        {:ok, emitted} = result

        try do
          golden = File.read!(golden_path)
          if canonical_lines(emitted) == canonical_lines(golden), do: :pass, else: :fail
        rescue
          _ -> :fail
        end

      true ->
        :error
    end
  end

  defp tally(results) do
    Enum.reduce(results, %{pass: 0, fail: 0, not_implemented: 0, error: 0}, fn r, acc ->
      Map.update!(acc, r, &(&1 + 1))
    end)
  end

  test "conformance scoreboard" do
    good = good_features()
    bad = bad_features()

    ast_results =
      for path <- good do
        basename = Path.basename(path)
        uri = upstream_uri("good", basename)
        data = File.read!(path)
        golden = path <> ".ast.ndjson"
        grade(Gherkin.Conformance.ast_ndjson(uri, data), golden)
      end

    pickle_results =
      for path <- good do
        basename = Path.basename(path)
        uri = upstream_uri("good", basename)
        data = File.read!(path)
        golden = path <> ".pickles.ndjson"
        grade(Gherkin.Conformance.pickles_ndjson(uri, data), golden)
      end

    error_results =
      for path <- bad do
        basename = Path.basename(path)
        uri = upstream_uri("bad", basename)
        data = File.read!(path)
        golden = path <> ".errors.ndjson"
        grade(Gherkin.Conformance.errors_ndjson(uri, data), golden)
      end

    ast = tally(ast_results)
    pickle = tally(pickle_results)
    err = tally(error_results)

    n_ast = length(ast_results)
    n_pickle = length(pickle_results)
    n_err = length(error_results)

    line = String.duplicate("=", 64)

    IO.puts("""

    #{line}
     GHERKIN CONFORMANCE SCOREBOARD  (upstream cucumber/gherkin testdata)
    #{line}
     AST     #{ast.pass}/#{n_ast}\tpass=#{ast.pass} fail=#{ast.fail} pending=#{ast.not_implemented} error=#{ast.error}
     Pickles #{pickle.pass}/#{n_pickle}\tpass=#{pickle.pass} fail=#{pickle.fail} pending=#{pickle.not_implemented} error=#{pickle.error}
     Errors  #{err.pass}/#{n_err}\tpass=#{err.pass} fail=#{err.fail} pending=#{err.not_implemented} error=#{err.error}
    #{line}
     Conformance: AST #{ast.pass}/#{n_ast}, Pickles #{pickle.pass}/#{n_pickle}, Errors #{err.pass}/#{n_err}
    #{line}
    """)

    # The harness must always run and produce a real count; it never goes red on a
    # not-yet-implemented pipeline. As the pipeline lands, the pass numbers climb and
    # the dedicated per-file assertions below (currently skipped) take over.
    assert n_ast > 0, "expected vendored good/ features"
    assert n_err > 0, "expected vendored bad/ features"
  end

  # When the pipeline is implemented, flip these into real per-file assertions (drop
  # the :pending moduletag or split this into its own module) so each corpus file is a
  # discrete pass/fail in the suite rather than just a tally line.
end
