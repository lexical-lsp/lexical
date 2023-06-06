defmodule Lexical.RemoteControl.CodeIntelligence.Ast do
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.RemoteControl.CodeIntelligence.Ast.Aliases

  def expand(%Document{} = document, %Position{} = position, module) do
    aliases_mapping = Aliases.at_position(document, position)
    module_path = module |> to_string() |> String.split(".")

    case module_path do
      ["__MODULE__"] ->
        aliases_mapping[module]

      ["Elixir", as_alias | tail] ->
        as = Module.concat([as_alias])
        alias = Map.get(aliases_mapping, as, as)
        Module.concat([alias | tail])

      ["Elixir" | _] ->
        Map.get(aliases_mapping, module, module)

      _ ->
        module
    end
  end
end
