defmodule Lexical.RemoteControl.CodeAction.Handler do
  alias Lexical.Document
  alias Lexical.Document.Changes
  alias Lexical.Document.Range
  alias Lexical.RemoteControl.CodeAction
  alias Lexical.RemoteControl.CodeAction.Diagnostic

  @callback actions(Document.t(), Range.t(), [Diagnostic.t()]) :: [Changes.t()]
  @callback kinds() :: [CodeAction.code_action_kind()]
end
