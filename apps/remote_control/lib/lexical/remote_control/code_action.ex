defmodule Lexical.RemoteControl.CodeAction do
  alias Lexical.Document
  alias Lexical.Document.Changes
  alias Lexical.Document.Range
  alias Lexical.RemoteControl.CodeAction.Diagnostic
  alias Lexical.RemoteControl.CodeAction.Handlers

  defstruct [:title, :kind, :changes, :uri]

  @type code_action_kind ::
          :empty
          | :quick_fix
          | :refactor
          | :refactor_extract
          | :refactor_inline
          | :refactor_rewrite
          | :source
          | :source_organize_imports
          | :source_fix_all

  @type t :: %__MODULE__{title: String.t(), kind: code_action_kind, changes: Changes.t()}

  @handlers [Handlers.ReplaceWithUnderscore]

  @spec new(Lexical.uri(), String.t(), code_action_kind(), Changes.t()) :: t()
  def new(uri, title, kind, changes) do
    %__MODULE__{uri: uri, title: title, changes: changes, kind: kind}
  end

  @spec for_range(Document.t(), Range.t(), [Diagnostic.t()], [code_action_kind | :all]) :: [t()]
  def for_range(%Document{} = doc, %Range{} = range, diagnostics, kinds) do
    results =
      Enum.reduce(@handlers, [], fn handler, acc ->
        if applies?(kinds, handler) do
          actions = handler.actions(doc, range, diagnostics)
          actions ++ acc
        else
          acc
        end
      end)

    results
  end

  defp applies?(:all, _handler_module) do
    true
  end

  defp applies?(kinds, handler_module) do
    requested_kinds = MapSet.new(kinds)
    handler_kinds = MapSet.new(handler_module.kinds())
    applicable_kinds = MapSet.intersection(requested_kinds, handler_kinds)
    not Enum.empty?(applicable_kinds)
  end
end
