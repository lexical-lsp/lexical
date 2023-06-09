defmodule LexicalCredo.MixProject do
  use Mix.Project

  def project do
    [
      app: :lexical_credo,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:lexical_plugin, path: "../lexical_plugin"},
      {:credo, "> 0.0.0", optional: true},
      {:jason, "> 0.0.0", optional: true}
    ]
  end
end
