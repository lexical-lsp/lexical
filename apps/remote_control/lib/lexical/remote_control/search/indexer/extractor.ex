defmodule Lexical.RemoteControl.Search.Indexer.Extractor do
  @moduledoc """
  Behaviour and helpers for extracting indexable information.
  """

  alias Lexical.Ast
  alias Lexical.Ast.Analysis
  alias Lexical.RemoteControl.Search.Indexer.Entry
  alias Lexical.RemoteControl.Search.Indexer.Extractors
  alias Sourceror.Zipper

  defstruct [:analysis, :current_scope, :current_zipper, entries: []]

  @type t :: %__MODULE__{
          analysis: Analysis.t(),
          entries: [Entry.t()],
          current_scope: Analysis.Scope.t(),
          current_zipper: Zipper.t()
        }

  @extractors [Extractors.Module]

  @doc """
  Extract information from the given element.
  """
  @callback extract(Zipper.t(), t) :: t

  @doc false
  def new(%Analysis{valid?: true} = analysis) do
    %__MODULE__{analysis: analysis}
  end

  @doc """
  Extract all information from the given analysis.
  """
  def index(%Analysis{valid?: true} = analysis) do
    extractor = new(analysis)
    extractor = Analysis.walk_zipper(analysis, extractor, &run_extractors/3)
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
        %Zipper{node: node},
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

    range = Ast.get_range(extractor.current_zipper.node, extractor.analysis)

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

  defp run_extractors(zipper, %Analysis.Scope{} = scope, %__MODULE__{} = extractor) do
    extractor = %__MODULE__{extractor | current_scope: scope, current_zipper: zipper}
    run_extractors(zipper, extractor)
  end

  defp run_extractors(zipper, nil, %__MODULE__{} = extractor) do
    extractor = %__MODULE__{extractor | current_zipper: zipper}
    run_extractors(zipper, extractor)
  end

  defp run_extractors(zipper, %__MODULE__{} = extractor) do
    Enum.reduce(@extractors, {zipper, extractor}, fn extractor_module, {zipper, extractor} ->
      %__MODULE__{} = extractor = extractor_module.extract(zipper, extractor)
      {zipper, extractor}
    end)
  end

  defp entries(%__MODULE__{entries: entries}) do
    Enum.reverse(entries)
  end
end
