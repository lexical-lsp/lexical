defmodule Lexical.Ast.Analysis.Scope do
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Analysis.Alias
  alias Lexical.Document.Position
  alias Lexical.Document.Range

  @enforce_keys [:id, :range, :kind]
  defstruct [
    :id,
    :range,
    :kind,
    module: [],
    aliases: [],
    parent_aliases: %{}
  ]

  @type t :: %__MODULE__{
          id: id,
          range: Range.t(),
          kind: kind,
          module: Analysis.module_segments(),
          aliases: [Alias.t()],
          parent_aliases: Analysis.alias_map()
        }

  @type id :: reference() | atom()

  @type kind :: :module | :def | :block

  @spec new(id, Range.t(), kind, Analysis.module_segments(), Analysis.alias_map()) :: t
  def new(id, %Range{} = range, kind \\ :block, module \\ [], parent_aliases \\ %{}) do
    %__MODULE__{id: id, range: range, kind: kind, module: module, parent_aliases: parent_aliases}
  end

  def root(%Range{} = range) do
    %__MODULE__{id: :root, kind: :block, range: range}
  end

  @spec alias_map(t(), Position.t() | :end) :: %{atom() => Alias.t()}
  def alias_map(%__MODULE__{} = scope, position \\ :end) do
    end_line =
      case position do
        :end -> scope.range.end.line
        %Position{line: line} -> line
      end

    scope.aliases
    # sorting by line ensures that aliases on later lines
    # override aliases on earlier lines
    |> Enum.sort_by(& &1.line)
    |> Enum.take_while(&(&1.line <= end_line))
    |> Map.new(&{&1.as, &1})
    |> Enum.into(scope.parent_aliases)
  end

  def empty?(%__MODULE__{} = scope) do
    root? = scope.id == :root
    has_aliases? = scope.aliases != []

    not (root? or has_aliases?)
  end
end
