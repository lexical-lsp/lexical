defmodule Proto.MixProject do
  use Mix.Project

  def project do
    [
      app: :proto,
      version: "0.5.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:jason, "~> 1.4", optional: true},
      {:lexical_shared, path: "../../projects/lexical_shared"},
      {:common, in_umbrella: true}
    ]
  end
end
