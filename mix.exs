defmodule Lexical.LanguageServer.MixProject do
  Code.require_file("mix_dialyzer.exs")
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
      dialyzer: Mix.Dialyzer.config(:lexical)
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.29.4", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:lexical_credo, path: "projects/lexical_credo", only: [:dev, :test]},
      Mix.Dialyzer.dependency()
    ]
  end

  defp docs do
    [
      main: "readme",
      deps: [jason: "https://hexdocs.pm/jason/Jason.html"],
      extras: ~w(
        README.md
        pages/installation.md
        pages/architecture.md
      ),
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
        include_erts: false,
        cookie: "lexical",
        rel_templates_path: "rel/deploy",
        strip_beams: false,
        steps: release_steps()
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

  def unconsolidate_jason(%Mix.Release{} = release) do
    # Consolidating Jason breaks the server for some reason. We need to investigate this
    jason_beam = Path.join([release.version_path, "consolidated", "Elixir.Jason.Encoder.beam"])
    File.rm(jason_beam)
    release
  end

  defp release_steps do
    if System.get_env("NAMESPACE") do
      [&namespace/1, :assemble, &namespace_release/1, &unconsolidate_jason/1]
    else
      [:assemble]
    end
  end

  defp namespace(%Mix.Release{} = release) do
    Mix.Task.run("namespace.beams", [release.path])
    release
  end

  defp namespace_release(%Mix.Release{} = release) do
    Mix.Task.run("namespace.release")
    release
  end

  defp clean(_) do
    Mix.Task.clear()
    Mix.Task.run("deps.clean", ~w(--all))
    Mix.Task.run("clean")
    Mix.Task.run("deps.get")
  end

  defp release_alias do
    if System.get_env("NAMESPACE") do
      [&clean/1, "release", &clean/1]
    else
      "release"
    end
  end

  defp aliases do
    [
      release: release_alias(),
      compile: "compile --docs --debug-info",
      docs: "docs --html",
      test: "test --no-start"
    ]
  end
end
