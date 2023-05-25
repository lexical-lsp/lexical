defmodule Lexical.Test.MixProject do
  use Mix.Project

  def project do
    [
      app: :lexical_test,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      deps_path: "../../deps"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    []
  end
end
