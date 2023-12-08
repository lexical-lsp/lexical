defmodule Lexical.Ast.Analysis.Analyzer.Scope do
  alias Lexical.Ast.Analysis.Analyzer.Alias
  alias Lexical.Document.Position
  alias Lexical.Document.Range

  defstruct [
    :id,
    :range,
    module: [],
    aliases: [],
    imports: []
  ]

  @type import_mfa :: {module(), atom(), non_neg_integer()}
  @type scope_position :: Position.t() | :end

  @type t :: %__MODULE__{
          id: any(),
          range: Range.t(),
          module: [atom()],
          aliases: [Alias.t()],
          imports: [import_mfa()]
        }

  def new(%__MODULE__{} = parent_scope, id, %Range{} = range, module \\ []) do
    %__MODULE__{
      id: id,
      aliases: parent_scope.aliases,
      imports: parent_scope.imports,
      module: module,
      range: range
    }
  end

  def global(%Range{} = range) do
    %__MODULE__{id: :global, range: range}
  end

  @spec alias_map(t(), scope_position()) :: %{module() => t()}
  def alias_map(%__MODULE__{} = scope, position \\ :end) do
    end_line = end_line(scope, position)

    scope.aliases
    # sorting by line ensures that aliases on later lines
    # override aliases on earlier lines
    |> Enum.sort_by(& &1.line)
    |> Enum.take_while(&(&1.line <= end_line))
    |> Map.new(&{&1.as, &1})
  end

  def fetch_alias_with_prefix(%__MODULE__{} = scope, prefix) do
    case Enum.find(scope.aliases, fn %Alias{} = alias -> alias.as == prefix end) do
      %Alias{} = existing -> {:ok, existing}
      _ -> :error
    end
  end

  def empty?(%__MODULE__{aliases: [], imports: []}), do: true
  def empty?(%__MODULE__{}), do: false

  def end_line(%__MODULE__{} = scope, :end), do: scope.range.end.line
  def end_line(_, %Position{} = position), do: position.line
end
