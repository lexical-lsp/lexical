defmodule Lexical.RemoteControl.MixProject do
  use Mix.Project

  def project do
    [
      app: :remote_control,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {module(), []}
    ]
  end

  defp elixirc_paths(:test) do
    ~w(lib test/support)
  end

  defp elixirc_paths(_) do
    ~w(lib)
  end

  defp module do
    if System.get_env("NAMESPACE") do
      LXRelease.RemoteControl.Application
    else
      Lexical.RemoteControl.Application
    end
  end

  defp deps do
    [
      {:common, in_umbrella: true},
      {:common_protocol, in_umbrella: true},
      {:path_glob, "~> 0.2", optional: true},
      {:elixir_sense, git: "https://github.com/elixir-lsp/elixir_sense.git", runtime: false},
      {:patch, "~> 0.12", only: [:dev, :test], optional: true, runtime: false}
    ]
  end
end
