defmodule Lexical.Shared.MixProject do
  use Mix.Project
  @repo_url "https://github.com/lexical-lsp/lexical"
  @version "0.5.0"

  def project do
    [
      app: :lexical_shared,
      version: @version,
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer_config(),
      package: package(),
      docs: docs()
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
      {:stream_data, "~> 1.1", only: [:test], runtime: false},
      {:ex_doc, "~> 0.34", only: [:dev]},
      {:patch, "~> 0.15", runtime: false, only: [:dev, :test]},
      dialyzer_dep()
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      description: "Shared data structures and protocols for the lexical language server",
      links: %{"Lexical LSP" => "https://github.com/lexical-lsp/lexical"},
      exclude_patterns: [
        "lib/lexical/document/store.ex"
      ]
    ]
  end

  defp docs do
    [
      extras: ["README.md": [title: "Overview"]],
      main: "Lexical",
      homepage_url: @repo_url,
      source_ref: "v#{@version}",
      source_url: @repo_url
    ]
  end

  def dialyzer_dep do
    path = Path.join([Path.dirname(__ENV__.file), "..", "..", "mix_dialyzer.exs"])

    if File.exists?(path) do
      Code.require_file(path)
      Mix.Dialyzer.dependency()
    else
      {:dialyxir, "> 0.0.0", only: [], runtime: false, optional: true}
    end
  end

  def dialyzer_config do
    if function_exported?(Mix.Dialyzer, :config, 0) do
      Mix.Dialyzer.config(:lexical_shared)
    else
      []
    end
  end
end
