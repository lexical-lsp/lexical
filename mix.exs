defmodule Lexical.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      aliases: aliases(),
      docs: docs(),
      name: "Lexical"
    ]
  end

  defp deps do
    [{:ex_doc, "~> 0.29.1", only: :dev, runtime: false}]
  end

  defp docs do
    [
      main: "Lexical",
      extras: ["README.md"],
      filter_modules: fn mod_name, _ ->
        case Module.split(mod_name) do
          ["Lexical", "Protocol" | _] -> false
          _ -> true
        end
      end
    ]
  end

  defp releases do
    [
      lexical: [
        applications: [
          server: :permanent,
          remote_control: :load,
          mix: :load
        ],
        include_executables_for: [:unix],
        include_erts: false,
        cookie: "lexical",
        strip_beams: false
      ],
      remote_control: [
        applications: [remote_control: :permanent],
        include_erts: false,
        include_executables_for: [],
        strip_beams: false
      ]
    ]
  end

  defp aliases do
    [
      compile: "compile --docs --debug-info",
      docs: "docs --html",
      test: "test --no-start"
    ]
  end
end
