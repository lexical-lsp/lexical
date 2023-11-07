defmodule Lexical.RemoteControl.CodeAction.Handlers.ReplaceRemoteFunction do
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.Document.Changes
  alias Lexical.Document.Edit
  alias Lexical.Document.Range
  alias Lexical.RemoteControl.CodeAction
  alias Lexical.RemoteControl.CodeAction.Diagnostic
  alias Sourceror.Zipper

  @behaviour CodeAction.Handler

  @impl CodeAction.Handler
  def actions(%Document{} = doc, %Range{}, diagnostics) do
    Enum.flat_map(diagnostics, fn %Diagnostic{} = diagnostic ->
      with {:ok, module, function, arity, line_number} <- extract_function_and_line(diagnostic),
           {:ok, suggestions} <- prepare_suggestions(module, function, arity) do
        to_code_actions(doc, line_number, module, function, suggestions)
      else
        _ ->
          []
      end
    end)
  end

  @impl CodeAction.Handler
  def kinds do
    [:quick_fix]
  end

  @spec to_code_actions(Document.t(), non_neg_integer(), module(), atom(), [atom()]) ::
          [CodeAction.t()]
  defp to_code_actions(%Document{} = doc, line_number, module, function, suggestions) do
    suggestions
    |> Enum.reduce([], fn suggestion, acc ->
      case apply_transform(doc, line_number, module, function, suggestion) do
        {:ok, edits} ->
          changes = Changes.new(doc, edits)
          code_action = CodeAction.new(doc.uri, "Rename to #{suggestion}", :quick_fix, changes)

          [code_action | acc]

        :error ->
          acc
      end
    end)
    |> Enum.reverse()
  end

  @spec apply_transform(Document.t(), non_neg_integer(), module(), atom(), atom()) ::
          {:ok, [Edit.t()]} | :error
  defp apply_transform(%Document{} = doc, line_number, module, function, suggestion) do
    doc
    |> Ast.traverse_line(line_number, [], fn
      %Zipper{node: {{:., _, [{:__aliases__, _, module_alias}, ^function]}, _, _} = node} = zipper,
      patches ->
        case Lexical.Ast.expand_aliases(module_alias, doc, {line_number, 0}) do
          {:ok, ^module} ->
            [patch] = Sourceror.Patch.rename_call(node, suggestion)
            {zipper, [patch | patches]}

          _ ->
            {zipper, patches}
        end

      zipper, patches ->
        {zipper, patches}
    end)
    |> case do
      {:ok, _zipper, patches} ->
        Ast.patches_to_edits(doc, patches)

      _ ->
        :error
    end
  end

  defp extract_function_and_line(%Diagnostic{} = diagnostic) do
    with {:ok, module, function, arity} <- extract_function(diagnostic.message),
         {:ok, line_number} <- extract_line(diagnostic) do
      {:ok, module, function, arity, line_number}
    end
  end

  @function_re ~r/(.*)\/(.*) is undefined or private. Did you mean:(.*)/
  defp extract_function(message) do
    with [[_, function, arity, _]] <- Regex.scan(@function_re, message),
         {:ok, module, function_name} <- separate_module_from_function(function) do
      {:ok, module, function_name, String.to_integer(arity)}
    end
  end

  defp separate_module_from_function(function) do
    function
    |> String.split(".")
    |> Enum.map(&String.to_atom/1)
    |> List.pop_at(-1)
    |> case do
      {function_name, [_ | _] = module_alias} -> {:ok, Module.concat(module_alias), function_name}
      _ -> :error
    end
  end

  defp extract_line(%Diagnostic{} = diagnostic) do
    {:ok, diagnostic.range.start.line}
  end

  @function_threshold 0.77
  @max_suggestions 5
  defp prepare_suggestions(module, function, arity) do
    function_as_string = Atom.to_string(function)

    suggestions =
      :functions
      |> module.__info__()
      |> Enum.filter(fn
        {_suggestion, ^arity} -> true
        _ -> false
      end)
      |> Enum.map(fn {suggestion, _arity} ->
        distance =
          suggestion
          |> Atom.to_string()
          |> String.jaro_distance(function_as_string)

        {suggestion, distance}
      end)
      |> Enum.filter(fn {_suggestion, distance} -> distance >= @function_threshold end)
      |> Enum.sort(&(elem(&1, 1) >= elem(&2, 1)))
      |> Enum.take(@max_suggestions)
      |> Enum.sort(&(elem(&1, 0) <= elem(&2, 0)))
      |> Enum.map(&elem(&1, 0))

    {:ok, suggestions}
  end
end
