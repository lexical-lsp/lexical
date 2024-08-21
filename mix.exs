defmodule Lexical.LanguageServer.MixProject do
  Code.require_file("mix_dialyzer.exs")
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.7.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
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
        pages/glossary.md
        pages/contributors_guide.md
      ),
      assets: [
        "pages/assets"
      ],
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
        Ast: ~r/Lexical.Ast/,
        Server: ~r/Lexical.Server/,
        Protocol: ~r/Lexical.Protocol/,
        "Protocol Requests": ~r/Lexical.Protocol.Requests/,
        "Protocol Responses": ~r/Lexical.Protocol.Responses/,
        "Protocol Notifications": ~r/Lexical.Protocol.Notifications/,
        Proto: ~r/(^Proto$|Lexical.Proto)/,
        RemoteControl: ~r/Lexical.RemoteControl/,
        Future: ~r/Future/
      ],
      nest_modules_by_prefix: [
        "Future",
        "Lexical.Server",
        "Lexical.Server.Project",
        "Lexical.Server.Provider",
        "Lexical.Server.CodeIntelligence",
        "Lexical.Server.CodeIntelligence.Completion",
        "Lexical.RemoteControl",
        "Lexical.RemoteControl.Analyzer",
        "Lexical.RemoteControl.Api",
        "Lexical.RemoteControl.Build",
        "Lexical.RemoteControl.Build.Document",
        "Lexical.RemoteControl.CodeAction",
        "Lexical.RemoteControl.CodeIntelligence",
        "Lexical.RemoteControl.Completion",
        "Lexical.RemoteControl.Search",
        "Lexical.RemoteControl.Search.CodeIntelligence",
        "Lexical.RemoteControl.Search.Indexer",
        "Lexical.RemoteControl.Search.Store",
        "Lexical.RemoteControl.Backend",
        "Lexical.Ast",
        "Lexical.Ast.Analysis",
        "Lexical.Ast.Detection",
        "Lexical.Protocol",
        "Lexical.Protocol.Requests",
        "Lexical.Protocol.Responses",
        "Lexical.Protocol.Notifications",
        "Lexical.Proto",
        "Lexical.Proto.LspTypes",
        "Lexical.Proto.Macros"
      ]
    ]
  end

  defp aliases do
    [
      compile: "compile --docs --debug-info",
      docs: "docs --html",
      test: "test --no-start",
      "nix.hash": &nix_hash/1
    ]
  end

  defp nix_hash(_args) do
    docker = System.get_env("DOCKER_CMD", "docker")

    Mix.shell().cmd(
      "#{docker} run --rm -v '#{File.cwd!()}:/data' nixos/nix nix --extra-experimental-features 'nix-command flakes' run ./data#update-hash",
      stderr_to_stdout: false
    )
  end
end
