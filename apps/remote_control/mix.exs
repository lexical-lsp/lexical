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
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Lexical.RemoteControl.Application, []}
    ]
  end

  defp deps do
    [
      {:common, in_umbrella: true},
      {:jason, "~> 1.4", optional: true},
      {:path_glob, "~> 0.2", optional: true},
      {:elixir_sense, git: "https://github.com/elixir-lsp/elixir_sense.git", runtime: false}
    ]
  end
end
