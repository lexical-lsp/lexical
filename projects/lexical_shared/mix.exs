defmodule Lexical.Shared.MixProject do
  use Mix.Project

  def project do
    [
      app: :lexical_shared,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      deps_path: "../../deps"
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
      {:stream_data, "~> 0.5", only: [:test], runtime: false},
      {:patch, "~> 0.12", runtime: false, only: [:dev, :test]}
    ]
  end
end
