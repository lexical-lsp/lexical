defmodule Lexical.LanguageServer.MixProject do
  Code.require_file("mix_dialyzer.exs")
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.7.2",
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
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
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
