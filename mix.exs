defmodule Gherkin.Mixfile do
  use Mix.Project

  @version "3.0.0"
  @source_url "https://github.com/cabbage-ex/gherkin"

  def project do
    [
      app: :gherkin,
      version: @version,
      elixir: "~> 1.18",
      source_url: @source_url,
      homepage_url: @source_url,
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: "Spec-conformant Gherkin (.feature) parser for Elixir",
      docs: [
        main: Gherkin,
        readme: "README.md",
        source_ref: "master"
      ],
      package: package(),
      deps: deps(),
      aliases: aliases(),
      # Built-in coverage (`mix test --cover`), replacing excoveralls. The summary is
      # informational, not a gate: threshold 0 keeps `--cover` from exiting non-zero
      # on coverage alone, so the test/conformance gates stay the source of CI truth.
      test_coverage: [summary: [threshold: 0]]
    ]
  end

  # The `conformance` alias is `mix test --only conformance`, so it must run in the
  # `:test` env. Without this, `mix conformance` from a default (dev) shell aborts
  # with "mix test is running in the dev environment". CI relies on this too.
  def cli, do: [preferred_envs: [conformance: :test]]

  def application do
    [extra_applications: [:logger, :runtime_tools]]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.29", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Matt Widmann", "Steve B", "Max Marcon", "Tomasz Tomczyk"],
      licenses: ["MIT"],
      # Explicit so the MIT LICENSE, changelog, and upgrade guide are always
      # shipped in the published tarball (not just relied on via Hex defaults).
      files: ~w(lib priv .formatter.exs mix.exs README.md CHANGELOG.md UPGRADING.md LICENSE),
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md"
      }
    ]
  end

  defp aliases do
    [
      publish: ["hex.publish", "hex.publish docs", "tag"],
      tag: &tag_release/1,
      # Run only the conformance suite and print the scoreboard. These tests are
      # tagged :conformance + :pending and are excluded from the default `mix test`.
      conformance: ["test --only conformance"]
    ]
  end

  defp tag_release(_) do
    Mix.shell().info("Tagging release as #{@version}")
    System.cmd("git", ["tag", "-a", "v#{@version}", "-m", "v#{@version}"])
    System.cmd("git", ["push", "--tags"])
  end
end
