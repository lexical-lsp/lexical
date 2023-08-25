defmodule Lexical.RemoteControl.MixProject do
  use Mix.Project

  def project do
    [
      app: :remote_control,
      version: "0.3.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :sasl, :eex],
      mod: {Lexical.RemoteControl.Application, []}
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
      {:beam_file, "~> 0.5.3"},
      {:common, in_umbrella: true},
      {:elixir_sense, git: "https://github.com/elixir-lsp/elixir_sense.git"},
      {:lexical_plugin, path: "../../projects/lexical_plugin"},
      {:lexical_shared, path: "../../projects/lexical_shared"},
      {:lexical_test, path: "../../projects/lexical_test", only: :test},
      {:patch, "~> 0.12", only: [:dev, :test], optional: true, runtime: false},
      {:path_glob, "~> 0.2", optional: true},
      {:sourceror, "~> 0.12"}
    ]
  end

  defp aliases do
    [test: "test --no-start"]
  end
end
