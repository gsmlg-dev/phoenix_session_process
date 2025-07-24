defmodule Phoenix.SessionProcess.MixProject do
  use Mix.Project

  @version "0.4.0"
  @source_url "https://github.com/gsmlg-dev/phoenix_session_process"

  def project do
    [
      app: :phoenix_session_process,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: description(),
      source_url: @source_url,
      package: [
        files: ["lib", "mix.exs", "README*", "LICENSE*", "CHANGELOG*"],
        maintainers: ["Jonathan Gao"],
        licenses: ["MIT"],
        links: %{"GitHub" => @source_url}
      ],
      deps: deps(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug, "~> 1.0"},
      {:telemetry, "~> 1.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    """
    Tool for create process for each user session in Phoenix.
    """
  end

  defp docs do
    [
      extras: ["CHANGELOG.md", "README.md"],
      source_url: @source_url,
      source_ref: "v#{@version}",
      main: "readme",
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end
end
