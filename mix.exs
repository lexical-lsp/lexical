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
      name: "Lexical",
      consolidate_protocols: Mix.env() != :test,
      dialyzer: dialyzer()
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.29.1", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.2", only: [:dev, :test], runtime: false}
    ]
  end

  defp dialyzer do
    [
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_deps: :apps_direct,
      plt_add_apps: [:wx, :mix, :ex_unit, :compiler]
    ]
  end

  defp docs do
    [
      main: "Lexical",
      deps: [jason: "https://hexdocs.pm/jason/Jason.html"],
      extras: ~w(README.md pages/architecture.md),
      filter_modules: fn mod_name, _ ->
        case Module.split(mod_name) do
          ["Lexical", "Protocol", "Requests" | _] -> true
          ["Lexical", "Protocol", "Notifications" | _] -> true
          ["Lexical", "Protocol", "Responses" | _] -> true
          ["Lexical", "Protocol" | _] -> false
          _ -> true
        end
      end,
      groups_for_modules: [
        Core: ~r/Lexical.^(RemoteControl|Protocol|Server)/,
        "Remote Control": ~r/Lexical.RemoteControl/,
        "Protocol Requests": ~r/Lexical.Protocol.Requests/,
        "Protocol Notifications": ~r/Lexical.Protocol.Notifications/,
        "Protocol Responses": ~r/Lexical.Protocol.Responses/,
        Server: ~r/Lexical.Server/
      ]
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
        include_erts: true,
        cookie: "lexical",
        rel_templates_path: "rel/deploy",
        strip_beams: false,
        steps: [&maybe_namespace/1, :assemble, &maybe_namespace_release/1]
      ],
      lexical_debug: [
        applications: [
          server: :permanent,
          remote_control: :load,
          mix: :load
        ],
        include_executables_for: [:unix],
        include_erts: false,
        path: "lexical_debug",
        cookie: "lexical",
        rel_templates_path: "rel/debug",
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

  defp maybe_namespace(%Mix.Release{} = release) do
    if System.get_env("NAMESPACE") do
      Mix.Task.run("namespace.beams", [release.path])
    end

    release
  end

  defp maybe_namespace_release(%Mix.Release{} = release) do
    if System.get_env("NAMESPACE") do
      Mix.Task.run("namespace.release")
    end

    release
  end

  defp maybe_clean(_) do
    if System.get_env("NAMESPACE") do
      Mix.Task.run("clean")
    end
  end

  defp aliases do
    [
      release: [&maybe_clean/1, "release", &maybe_clean/1],
      compile: "compile --docs --debug-info",
      credo: "credo --strict",
      docs: "docs --html",
      test: "test --no-start"
    ]
  end
end
