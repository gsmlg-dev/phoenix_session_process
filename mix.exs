defmodule Phoenix.SessionProcess.MixProject do
  use Mix.Project

  def project do
    [
      app: :phoenix_session_process,
      version: "0.1.0",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: description(),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/gsmlg-dev/phoenix_session_process"},
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
