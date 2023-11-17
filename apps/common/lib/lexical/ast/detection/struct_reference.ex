defmodule Lexical.Ast.Detection.StructReference do
  alias Lexical.Ast
  alias Lexical.Ast.Detection
  alias Lexical.Ast.Tokens
  alias Lexical.Document
  alias Lexical.Document.Position

  use Detection

  @impl Detection
  def detected?(%Document{} = document, %Position{} = position) do
    case Ast.cursor_context(document, position) do
      {:ok, {:struct, []}} ->
        false

      {:ok, {:struct, _}} ->
        true

      {:ok, {:local_or_var, [?_ | _rest] = possible_module_struct}} ->
        # a reference to `%__MODULE`, often in a function head, as in
        # def foo(%__)

        starts_with_percent? =
          document
          |> Tokens.prefix_stream(position)
          |> Enum.take(2)
          |> Enum.any?(fn
            {:percent, :%, _} -> true
            _ -> false
          end)

        starts_with_percent? and possible_dunder_module(possible_module_struct) and
          (ancestor_is_def?(document, position) or ancestor_is_type?(document, position))

      _ ->
        false
    end
  end

  def possible_dunder_module(charlist) do
    String.starts_with?("__MODULE__", to_string(charlist))
  end
end
