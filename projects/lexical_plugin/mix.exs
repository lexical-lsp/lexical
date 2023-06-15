defmodule Lexical.Plugin.MixProject do
  Code.require_file("../../mix_dialyzer.exs")
  use Mix.Project

  def project do
    [
      app: :lexical_plugin,
      aliases: aliases(),
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      build_path: "../../_build",
      deps_path: "../../deps",
      dialyzer: Mix.Dialyzer.config()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Lexical.Plugin.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:lexical_shared, path: "../lexical_shared"},
      {:ex_doc, "~> 0.29", only: :dev},
      Mix.Dialyzer.dependency()
    ]
  end

  defp aliases do
    [
      test: "test --no-start"
    ]
  end
end
