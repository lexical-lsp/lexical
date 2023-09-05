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
      {:ok, normalize_docs(module, module_doc, docs)}
    end
  end

  defp normalize_docs(module, module_doc, element_docs) do
    elements_by_kind = Enum.group_by(element_docs, &doc_kind/1)
    functions = Map.get(elements_by_kind, :function, [])
    macros = Map.get(elements_by_kind, :macro, [])
    callbacks = Map.get(elements_by_kind, :callback, [])
    types = Map.get(elements_by_kind, :type, [])

    %__MODULE__{
      module: module,
      doc: Entry.parse_doc(module_doc),
      functions_and_macros: parse_doc_elements(module, functions ++ macros),
      callbacks: parse_doc_elements(module, callbacks),
      types: parse_doc_elements(module, types)
    }
  end

  defp doc_kind({{kind, _name, _arity}, _anno, _sig, _doc, _meta}) do
    kind
  end

  defp parse_doc_elements(module, elements) do
    elements
    |> Enum.map(&Entry.from_docs_v1(module, &1))
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
end
