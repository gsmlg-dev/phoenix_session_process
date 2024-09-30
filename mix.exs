defmodule Phoenix.SessionProcess.MixProject do
  use Mix.Project

  def project do
    [
      app: :phoenix_session_process,
      version: "0.3.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: description(),
      source_url: "https://github.com/gsmlg-dev/phoenix_session_process",
      package: [
        files: ["lib", "mix.exs", "README*", "LICENSE*", "CHANGELOG*"],
        maintainers: ["Jonathan Gao"],
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/gsmlg-dev/phoenix_session_process"}
      ],
      deps: deps()
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
end
