defmodule Lexical.RemoteControl.CodeIntelligence.Docs do
  @moduledoc """
  Utilities for fetching documentation for a compiled module.
  """

  alias Lexical.RemoteControl.CodeIntelligence.Docs.Entry

  defstruct [:module, :doc, functions_and_macros: [], callbacks: [], types: []]

  @type t :: %__MODULE__{
          module: module(),
          doc: Entry.content(),
          functions_and_macros: %{optional(atom()) => [Entry.t(:function | :macro)]},
          callbacks: %{optional(atom()) => [Entry.t(:callback)]},
          types: %{optional(atom()) => [Entry.t(:type)]}
        }

  @doc """
  Fetches known documentation for the given module.
  """
  @spec for_module(module()) :: {:ok, t} | {:error, any()}
  def for_module(module) when is_atom(module) do
    with :ok <- ensure_ready(module),
         {:docs_v1, _anno, _lang, _fmt, module_doc, _meta, docs} <- Code.fetch_docs(module) do
      {:ok, parse_docs(module, module_doc, docs)}
    end
  end

  defp parse_docs(module, module_doc, entries) do
    entries_by_kind = Enum.group_by(entries, &doc_kind/1)
    function_entries = Map.get(entries_by_kind, :function, [])
    macro_entries = Map.get(entries_by_kind, :macro, [])
    callback_entries = Map.get(entries_by_kind, :callback, [])
    type_entries = Map.get(entries_by_kind, :type, [])

    spec_defs = get_spec_defs(module)
    callback_defs = get_callback_defs(module)
    type_defs = get_type_defs(module)

    %__MODULE__{
      module: module,
      doc: Entry.parse_doc(module_doc),
      functions_and_macros: parse_entries(module, function_entries ++ macro_entries, spec_defs),
      callbacks: parse_entries(module, callback_entries, callback_defs),
      types: parse_entries(module, type_entries, type_defs)
    }
  end

  defp doc_kind({{kind, _name, _arity}, _anno, _sig, _doc, _meta}) do
    kind
  end

  defp parse_entries(module, raw_entries, defs) do
    defs_by_name_arity =
      Enum.group_by(
        defs,
        fn {name, arity, _formatted} -> {name, arity} end,
        fn {_name, _arity, formatted} -> formatted end
      )

    raw_entries
    |> Enum.map(fn raw_entry ->
      entry = Entry.from_docs_v1(module, raw_entry)
      defs = Map.get(defs_by_name_arity, {entry.name, entry.arity}, [])
      Map.replace!(entry, :defs, defs)
    end)
    |> Enum.group_by(& &1.name)
  end

  defp ensure_ready(module) do
    with {:module, _} <- Code.ensure_compiled(module),
         path when is_list(path) and path != [] <- :code.which(module) do
      ensure_file_exists(path)
    else
      _ -> {:error, :not_found}
    end
  end

  @timeout 10
  defp ensure_file_exists(path, attempts \\ 10)

  defp ensure_file_exists(_, 0) do
    {:error, :beam_file_timeout}
  end

  defp ensure_file_exists(path, attempts) do
    if File.exists?(path) do
      :ok
    else
      Process.sleep(@timeout)
      ensure_file_exists(path, attempts - 1)
    end
  end

  defp get_spec_defs(module) do
    case Code.Typespec.fetch_specs(module) do
      {:ok, specs} ->
        for {{name, arity}, defs} <- specs,
            def <- defs do
          formatted = name |> Code.Typespec.spec_to_quoted(def) |> format_def()
          {name, arity, formatted}
        end

      _ ->
        []
    end
  end

  defp get_callback_defs(module) do
    case Code.Typespec.fetch_callbacks(module) do
      {:ok, callbacks} ->
        for {{name, arity}, defs} <- callbacks,
            def <- defs do
          formatted = name |> Code.Typespec.spec_to_quoted(def) |> format_def()
          {name, arity, formatted}
        end

      _ ->
        []
    end
  end

  defp get_type_defs(module) do
    case Code.Typespec.fetch_types(module) do
      {:ok, types} ->
        for {kind, {name, _body, args} = type} <- types do
          arity = length(args)
          quoted_type = Code.Typespec.type_to_quoted(type)
          quoted = {:@, [], [{kind, [], [quoted_type]}]}

          {name, arity, format_def(quoted)}
        end

      _ ->
        []
    end
  end

  defp format_def(quoted) do
    quoted
    |> Future.Code.quoted_to_algebra()
    |> Inspect.Algebra.format(60)
    |> IO.iodata_to_binary()
  end
end
