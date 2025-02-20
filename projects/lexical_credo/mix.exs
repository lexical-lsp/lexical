defmodule LexicalCredo.MixProject do
  use Mix.Project

  @repo_url "https://github.com/lexical-lsp/lexical/"
  @version "0.5.0"

  def project do
    [
      app: :lexical_credo,
      version: @version,
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      env: [lexical_plugin: true]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      env_dep(
        hex: {:lexical_plugin, "~> 0.5"},
        else: {:lexical_plugin, path: "../lexical_plugin"}
      ),
      {:credo, "> 0.0.0", optional: true},
      {:jason, "> 0.0.0", optional: true},
      {:ex_doc, "~> 0.34", optional: true, only: [:dev, :hex]}
    ]
  end

  defp docs do
    [
      extras: ["README.md": [title: "Overview"]],
      main: "readme",
      homepage_url: @repo_url,
      source_ref: "v#{@version}",
      source_url: @repo_url
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      description: "A plugin for the lexical language server that enables Credo checks",
      links: %{
        "Lexical Credo" => "https://github.com/lexical-lsp/lexical",
        "Credo" => "https://github.com/rrrene/credo"
      }
    ]
  end

  defp env_dep(opts) do
    case Keyword.fetch(opts, Mix.env()) do
      {:ok, dep} -> dep
      :error -> Keyword.fetch!(opts, :else)
    end
  end
end
