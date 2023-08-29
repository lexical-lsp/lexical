defmodule Lexical.RemoteControl.Search.Indexer.Extractors.Module do
  @moduledoc """
  Extracts module references and definitions from AST
  """

  alias Lexical.Ast.Aliases
  alias Lexical.ProcessCache
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Indexer.Metadata
  alias Lexical.RemoteControl.Search.Indexer.Source.Block
  alias Lexical.RemoteControl.Search.Indexer.Source.Reducer

  # extract a module definition
  def extract(
        {:defmodule, defmodule_meta,
         [{:__aliases__, module_name_meta, module_name}, module_block]},
        %Reducer{} = reducer
      ) do
    %Block{} = block = Reducer.current_block(reducer)
    aliased_module = resolve_alias(reducer, module_name)

    entry =
      Entry.definition(
        reducer.document.path,
        block.ref,
        block.parent_ref,
        aliased_module,
        :module,
        reducer.position,
        block.ends_at,
        Application.get_application(aliased_module)
      )

    module_name_meta = Reducer.skip(module_name_meta)

    elem =
      {:defmodule, defmodule_meta, [{:__aliases__, module_name_meta, module_name}, module_block]}

    {:ok, entry, elem}
  end

  # This matches an elixir module reference
  def extract({:__aliases__, metadata, maybe_module}, %Reducer{} = reducer)
      when is_list(maybe_module) do
    case module(reducer, maybe_module) do
      {:ok, module} ->
        start = Metadata.position(metadata)
        finish = Metadata.position(metadata, :last)

        %Block{} = current_block = Reducer.current_block(reducer)

        entry =
          Entry.reference(
            reducer.document.path,
            make_ref(),
            current_block.ref,
            module,
            :module,
            start,
            finish,
            Application.get_application(module)
          )

        {:ok, entry}

      _ ->
        :ignored
    end
  end

  # This matches an erlang module, which is just an atom
  def extract(atom_literal, %Reducer{} = reducer) when is_atom(atom_literal) do
    case module(reducer, atom_literal) do
      {:ok, module} ->
        %Block{} = current_block = Reducer.current_block(reducer)
        {start_line, start_column} = start = reducer.position
        atom_length = module |> Atom.to_string() |> String.length()
        finish = {start_line, start_column + atom_length}

        entry =
          Entry.reference(
            reducer.document.path,
            make_ref(),
            current_block.ref,
            module,
            :module,
            start,
            finish,
            Application.get_application(module)
          )

        {:ok, entry}

      :error ->
        :ignored
    end
  end

  def extract(_, _) do
    :ignored
  end

  defp resolve_alias(%Reducer{} = reducer, unresolved_alias) do
    [first_element | rest] = unresolved_alias

    with {:ok, aliases} <- Aliases.at_ast(reducer.quoted_document, reducer.position),
         {:ok, aliased} <- Map.fetch(aliases, first_element) do
      raw = Module.split(aliased)
      Module.concat(raw ++ rest)
    else
      _ ->
        Module.concat(unresolved_alias)
    end
  end

  defp module(%Reducer{} = reducer, maybe_module) when is_list(maybe_module) do
    if Enum.all?(maybe_module, &module_part?/1) do
      resolved = resolve_alias(reducer, maybe_module)
      {:ok, resolved}
    else
      :error
    end
  end

  defp module(%Reducer{}, maybe_erlang_module) when is_atom(maybe_erlang_module) do
    if available_module?(maybe_erlang_module) do
      {:ok, maybe_erlang_module}
    else
      :error
    end
  end

  defp module(_, _), do: :error

  @starts_with_capital ~r/[A-Z]+/
  defp module_part?(part) when is_atom(part) do
    Regex.match?(@starts_with_capital, Atom.to_string(part))
  end

  defp module_part?(_), do: false

  defp available_module?(potential_module) do
    MapSet.member?(all_modules(), potential_module)
  end

  defp all_modules do
    ProcessCache.trans(:all_modules, fn ->
      MapSet.new(:code.all_available(), fn {module_charlist, _, _} ->
        List.to_atom(module_charlist)
      end)
    end)
  end
end
