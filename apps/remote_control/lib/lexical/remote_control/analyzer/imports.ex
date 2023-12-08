defmodule Lexical.RemoteControl.Analyzer.Imports do
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Analysis.Analyzer
  alias Lexical.Ast.Analysis.Analyzer.Import
  alias Lexical.Ast.Analysis.Analyzer.Scope
  alias Lexical.Document.Position
  alias Lexical.ProcessCache
  alias Lexical.RemoteControl.Analyzer.Aliases
  alias Lexical.RemoteControl.Analyzer.Scopes
  alias Lexical.RemoteControl.Module.Loader

  @kernel_imports [
    Import.new([:Kernel], 1),
    Import.new([:Kernel, :SpecialForms], 1)
  ]

  @spec at(Analysis.t(), Position.t()) :: [Import.t()]
  def(at(%Analysis{} = analysis, %Position{} = position)) do
    case Scopes.at(analysis, position) do
      [%Analyzer.Scope{} = scope | _] ->
        imports(scope, position)

      _ ->
        []
    end
  end

  @spec imports(Scope.t(), Scope.scope_position()) :: [Scope.import_mfa()]
  def imports(%Analyzer.Scope{} = scope, position \\ :end) do
    scope
    |> import_map(position)
    |> Map.values()
    |> List.flatten()
  end

  defp import_map(%Analyzer.Scope{} = scope, position) do
    end_line = Scope.end_line(scope, position)

    (@kernel_imports ++ scope.imports)
    # sorting by line ensures that imports on later lines
    # override imports on earlier lines
    |> Enum.sort_by(& &1.line)
    |> Enum.take_while(&(&1.line <= end_line))
    |> Enum.reduce(%{}, fn %Analyzer.Import{} = import, current_imports ->
      apply_to_scope(import, scope, current_imports)
    end)
  end

  defp apply_to_scope(%Import{} = import, current_scope, %{} = current_imports) do
    import_module = Aliases.resolve_at(current_scope, import.module, import.line)

    functions = mfas_for(import_module, :functions)
    macros = mfas_for(import_module, :macros)

    case import.selector do
      :all ->
        Map.put(current_imports, import_module, functions ++ macros)

      [only: :functions] ->
        Map.put(current_imports, import_module, functions)

      [only: :macros] ->
        Map.put(current_imports, import_module, macros)

      [only: functions_to_import] ->
        functions_to_import = function_and_arity_to_mfa(import_module, functions_to_import)
        Map.put(current_imports, import_module, functions_to_import)

      [except: functions_to_except] ->
        # This one is a little tricky. Imports using except have two cases.
        # In the first case, if the module hasn't been previously imported, we
        # collect all the functions in the current module and remove the ones in the
        # except clause.
        # If the module has been previously imported, we just remove the functions from
        # the except clause from those that have been previously imported.
        # See: https://hexdocs.pm/elixir/1.13.0/Kernel.SpecialForms.html#import/2-selector

        functions_to_except = function_and_arity_to_mfa(import_module, functions_to_except)

        if already_imported?(current_imports, import_module) do
          Map.update!(current_imports, import_module, fn old_imports ->
            old_imports -- functions_to_except
          end)
        else
          to_import = (functions ++ macros) -- functions_to_except
          Map.put(current_imports, import_module, to_import)
        end
    end
  end

  defp already_imported?(%{} = current_imports, imported_module) do
    case current_imports do
      %{^imported_module => [_ | _]} -> true
      _ -> false
    end
  end

  defp function_and_arity_to_mfa(current_module, fa_list) when is_list(fa_list) do
    Enum.map(fa_list, fn {function, arity} -> {current_module, function, arity} end)
  end

  defp mfas_for(current_module, type) do
    if Loader.ensure_loaded?(current_module) do
      fa_list = function_and_arities_for_module(current_module, type)

      function_and_arity_to_mfa(current_module, fa_list)
    else
      []
    end
  end

  defp function_and_arities_for_module(module, type) do
    ProcessCache.trans({module, :info, type}, fn ->
      type
      |> module.__info__()
      |> Enum.reject(fn {name, _arity} ->
        name |> Atom.to_string() |> String.starts_with?("_")
      end)
    end)
  end
end
