defmodule Lexical.Protocol.MixProject do
  use Mix.Project

  def project do
    [
      app: :protocol,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      consolidate_protocols: Mix.env() != :test,
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ~w(lib test/support)
  defp elixirc_paths(_), do: ~w(lib)

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:lexical, path: "../../projects/lexical"},
      {:lexical_test, path: "../../projects/lexical_test", only: :test},
      {:common, in_umbrella: true},
      {:jason, "~> 1.4", optional: true},
      {:patch, "~> 0.12", only: [:test]},
      {:proto, in_umbrella: true}
    ]
  end
end
