defmodule Gherkin.Mixfile do
  use Mix.Project

  @version "2.0.0"
  def project do
    [
      app: :gherkin,
      version: @version,
      elixir: "~> 1.3",
      source_url: "https://github.com/cabbage-ex/gherkin",
      homepage_url: "https://github.com/cabbage-ex/gherkin",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: "Gherkin file parser for Elixir",
      docs: [
        main: Gherkin,
        readme: "README.md",
        source_ref: "master"
      ],
      package: package(),
      deps: deps(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls]
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
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:excoveralls, "~> 0.10", only: :test}
    ]
  end

  defp package do
    [
      maintainers: ["Matt Widmann", "Steve B"],
      licenses: ["MIT"],
      links: %{github: "https://github.com/cabbage-ex/gherkin"}
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
