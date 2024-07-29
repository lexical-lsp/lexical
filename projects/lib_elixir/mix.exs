defmodule LibElixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :lib_elixir,
      version: "0.1.0",
      elixir: ">= 1.13.4",
      compilers: Mix.compilers() ++ [:lib_elixir],
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :sasl, :crypto]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.5.0"}
    ]
  end
end
