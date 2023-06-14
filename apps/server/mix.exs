defmodule Lexical.Server.MixProject do
  use Mix.Project

  def project do
    [
      app: :server,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools, :kernel, :erts],
      mod: {module(), []}
    ]
  end

  def aliases do
    [
      test: "test --no-start"
    ]
  end

  defp module do
    if System.get_env("NAMESPACE") do
      LXRelease.Server.Application
    else
      Lexical.Server.Application
    end
  end

  defp elixirc_paths(:test) do
    ["lib", "test/support"]
  end

  defp elixirc_paths(_) do
    ["lib"]
  end

  defp deps do
    [
      {:lexical_shared, path: "../../projects/lexical_shared", override: true},
      {:lexical_test, path: "../../projects/lexical_test", only: :test},
      {:common, in_umbrella: true},
      {:elixir_sense, github: "elixir-lsp/elixir_sense"},
      {:jason, "~> 1.4"},
      {:logger_file_backend, "~> 0.0.13", only: [:dev, :prod]},
      {:patch, "~> 0.12", runtime: false, only: [:dev, :test]},
      {:path_glob, "~> 0.2"},
      {:protocol, in_umbrella: true},
      {:remote_control, in_umbrella: true, runtime: false}
    ]
  end
end
