defmodule Lexical.RemoteControl.Completion do
  alias Lexical.Ast
  alias Lexical.Ast.Analysis
  alias Lexical.Document.Position
  alias Lexical.RemoteControl.Completion.Candidate

  def elixir_sense_expand(doc_string, %Position{} = position) do
    line = position.line
    character = position.character
    hint = ElixirSense.Core.Source.prefix(doc_string, line, character)

    if String.trim(hint) == "" do
      []
    else
      for suggestion <- ElixirSense.suggestions(doc_string, line, character),
          candidate = Candidate.from_elixir_sense(suggestion),
          candidate != nil do
        candidate
      end
    end
  end

  def struct_fields(%Analysis{} = analysis, %Position{} = position) do
    container_struct_module =
      analysis
      |> Lexical.Ast.cursor_path(position)
      |> container_struct_module()

    with {:ok, struct_module} <- Ast.expand_alias(container_struct_module, analysis, position),
         true <- function_exported?(struct_module, :__struct__, 0) do
      struct_module
      |> struct()
      |> Map.from_struct()
      |> Map.keys()
      |> Enum.map(&Candidate.StructField.new(&1, struct_module))
    else
      _ -> []
    end
  end

  defp container_struct_module(cursor_path) do
    Enum.find_value(cursor_path, fn
      # current module struct: `%__MODULE__{|}`
      {:%, _, [{:__MODULE__, _, _} | _]} -> [:__MODULE__]
      # struct leading by current module: `%__MODULE__.Struct{|}`
      {:%, _, [{:__aliases__, _, [{:__MODULE__, _, _} | tail]} | _]} -> [:__MODULE__ | tail]
      # Struct leading by alias or just a aliased Struct: `%Struct{|}`, `%Project.Struct{|}`
      {:%, _, [{:__aliases__, _, aliases} | _]} -> aliases
      _ -> nil
    end)
  end
end
