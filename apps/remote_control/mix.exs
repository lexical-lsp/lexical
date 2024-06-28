defmodule Lexical.RemoteControl.MixProject do
  use Mix.Project

  def project do
    [
      app: :remote_control,
      version: "0.5.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      preferred_cli_env: [benchmark: :test]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :sasl, :eex],
      mod: {Lexical.RemoteControl.Application, []}
    ]
  end

  # cli/0 is new for elixir 1.15, prior, we need to set `preferred_cli_env` in the project
  def cli do
    [
      preferred_envs: [benchmark: :test]
    ]
  end

  defp elixirc_paths(:test) do
    ~w(lib test/support)
  end

  defp elixirc_paths(_) do
    ~w(lib)
  end

  defp deps do
    [
      {:benchee, "~> 1.1", only: :test},
      {:common, in_umbrella: true},
      {:elixir_sense, git: "https://github.com/elixir-lsp/elixir_sense.git"},
      {:lexical_plugin, path: "../../projects/lexical_plugin"},
      {:lexical_shared, path: "../../projects/lexical_shared"},
      {:lexical_test, path: "../../projects/lexical_test", only: :test},
      {:patch, "~> 0.12", only: [:dev, :test], optional: true, runtime: false},
      {:path_glob, "~> 0.2", optional: true},
      {:phoenix_live_view, "~> 0.19.5", only: [:test], optional: true, runtime: false},
      {:snowflake, "~> 1.0"},
      {:sourceror, "~> 1.4"}
    ]
  end

  defp aliases do
    [test: "test --no-start", benchmark: "run"]
  end
end
