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
        links: %{
          "GitHub" => @source_url,
          "Documentation" => "https://hexdocs.pm/phoenix_session_process",
          "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
        },
        description: "Session isolation and state management for Phoenix applications"
      ],
      deps: deps(),
      docs: docs(),
      aliases: aliases()
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
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    """
    Phoenix.SessionProcess creates a dedicated process for each user session in Phoenix applications.

    This library provides session isolation, state management, and automatic cleanup with TTL support.
    Each user session runs in its own GenServer process, enabling real-time session state
    without external dependencies like Redis or databases.

    Key features:
    - Session isolation with dedicated GenServer processes
    - Automatic cleanup with configurable TTL
    - LiveView integration for reactive UIs
    - High performance (10,000+ sessions/second)
    - Built-in telemetry and monitoring
    - Zero external dependencies beyond core Phoenix/OTP
    """
  end

  defp docs do
    [
      name: "Phoenix.SessionProcess",
      source_ref: "v#{@version}",
      main: "readme",
      source_url: @source_url,
      homepage_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        "Guides": [
          "README.md"
        ],
        "Reference": [
          "CHANGELOG.md",
          "LICENSE"
        ]
      ],
      groups_for_modules: [
        "Core API": [
          Phoenix.SessionProcess,
          Phoenix.SessionProcess.SessionId
        ],
        "Configuration": [
          Phoenix.SessionProcess.Config
        ],
        "Error Handling": [
          Phoenix.SessionProcess.Error
        ],
        "Internals": [
          Phoenix.SessionProcess.Supervisor,
          Phoenix.SessionProcess.ProcessSupervisor,
          Phoenix.SessionProcess.Cleanup,
          Phoenix.SessionProcess.DefaultSessionProcess
        ],
        "Utilities": [
          Phoenix.SessionProcess.Helpers,
          Phoenix.SessionProcess.Telemetry,
          Phoenix.SessionProcess.State,
          Phoenix.SessionProcess.Redux,
          Phoenix.SessionProcess.MigrationExamples
        ]
      ],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end

  defp aliases do
    [
      lint: ["credo --strict", "dialyzer"]
    ]
  end
end
