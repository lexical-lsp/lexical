defmodule CommonProtocol.MixProject do
  use Mix.Project

  def project do
    [
      app: :common_protocol,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.14",
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
      {:proto, in_umbrella: true, runtime: false},
      {:jason, "~> 1.4", optional: true}
    ]
  end
end
