defmodule Lexical.RemoteControl.Search.Indexer.Extractor do
  @moduledoc """
  Behaviour and helpers for extracting indexable information.
  """

  alias Lexical.Ast
  alias Lexical.Ast.Analysis
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Indexer.Extractors

  defstruct [:analysis, :current_node, :ancestors, entries: []]

  @type t :: %__MODULE__{
          analysis: Analysis.t(),
          entries: [Entry.t()],
          current_node: Macro.t(),
          ancestors: [Macro.t()]
        }

  @extractors [Extractors.Module]

  @doc """
  Extract information from the given element.
  """
  @callback extract(Macro.t(), t) :: t

  @doc false
  def new(%Analysis{valid?: true} = analysis) do
    %__MODULE__{analysis: analysis}
  end

  @doc """
  Extract all information from the given analysis.
  """
  def index(%Analysis{valid?: true} = analysis) do
    extractor = new(analysis)
    extractor = Ast.traverse_with_ancestors(analysis, extractor, &run_extractors/3)
    {:ok, entries(extractor)}
  end

  def index(%Analysis{valid?: false}) do
    {:ok, []}
  end

  @doc """
  Records an indexed entry.
  """
  def record_entry(
        %__MODULE__{} = extractor,
        node,
        type,
        subtype,
        subject,
        application,
        opts \\ []
      ) do
    id = Analysis.get_node_id(node)

    parent_kind = opts |> Keyword.validate!(parent_kind: :any) |> Keyword.fetch!(:parent_kind)

    parent_scope_id =
      Analysis.get_parent_id(
        node,
        parent_kind,
        extractor.analysis
      )

    range = Ast.get_range(extractor.current_node, extractor.analysis)

    entry =
      Entry.new(
        extractor.analysis.document.path,
        id,
        parent_scope_id || :root,
        subject,
        type,
        subtype,
        range,
        application
      )

    %__MODULE__{extractor | entries: [entry | extractor.entries]}
  end

  defp run_extractors(node, ancestors, %__MODULE__{} = extractor) do
    extractor = %__MODULE__{extractor | current_node: node, ancestors: ancestors}
    run_extractors(node, extractor)
  end

  defp run_extractors(node, %__MODULE__{} = extractor) do
    Enum.reduce(@extractors, {node, extractor}, fn extractor_module, {node, extractor} ->
      %__MODULE__{} = extractor_module.extract(node, extractor)
    end)
  end

  defp entries(%__MODULE__{entries: entries}) do
    Enum.reverse(entries)
  end
end
