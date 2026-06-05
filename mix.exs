defmodule Gherkin.Mixfile do
  use Mix.Project

  @version "2.0.0"

  # NOTE: the hex package name and `app:` are intentionally left as `:gherkin`.
  # Renaming the published package is a separate, deferred decision; this fork
  # only retargets the source/homepage/links metadata below.
  @source_url "https://github.com/tomasz-tomczyk/gherkin"

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

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [extra_applications: [:logger, :runtime_tools]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:ex_doc, "~> 0.29", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Matt Widmann", "Steve B", "Max Marcon", "Tomasz Tomczyk"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Upstream (cabbage-ex/gherkin)" => "https://github.com/cabbage-ex/gherkin"
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
