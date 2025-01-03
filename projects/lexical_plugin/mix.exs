defmodule Lexical.Plugin.MixProject do
  use Mix.Project

  @version "0.5.0"
  def project do
    [
      app: :lexical_plugin,
      aliases: aliases(),
      version: @version,
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer_config(),
      package: package(),
      docs: docs()
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      env_dep(
        hex: {:lexical_shared, "~> 0.5"},
        else: {:lexical_shared, path: "../lexical_shared"}
      ),
      env_dep(
        hex: {:ex_doc, "~> 0.34", only: :hex, runtime: false},
        else: {:ex_doc, "~> 0.34", only: :dev, runtime: false}
      ),
      dialyzer_dep()
    ]
  end

  defp env_dep(opts) do
    case Keyword.fetch(opts, Mix.env()) do
      {:ok, dep} -> dep
      :error -> Keyword.fetch!(opts, :else)
    end
  end

  defp aliases do
    [
      test: "test --no-start"
    ]
  end

  defp package do
    [
      description: "The package you need to build plugins for the lexical language server",
      licenses: ["Apache-2.0"],
      links: %{"Lexical LSP" => "https://github.com/lexical-lsp/lexical"}
    ]
  end

  defp docs do
    [
      extras: ["README.md": [title: "Overview"]],
      main: "readme",
      source_ref: "v#{@version}"
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
      Mix.Dialyzer.config(:lexical_plugin)
    else
      []
    end
  end
end
