defmodule Common.MixProject do
  use Mix.Project

  def project do
    [
      app: :common,
      version: "0.3.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test) do
    ["lib", "test/support"]
  end

  defp elixirc_paths(_) do
    ["lib"]
  end

  defp deps do
    [
      {:lexical_shared, path: "../../projects/lexical_shared"},
      {:sourceror, "~> 0.14.1"},
      {:stream_data, "~> 0.6", only: [:test], runtime: false},
      {:patch, "~> 0.12", only: [:test], optional: true, runtime: false}
    ]
  end
end
