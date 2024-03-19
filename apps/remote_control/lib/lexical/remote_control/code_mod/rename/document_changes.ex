defmodule Lexical.RemoteControl.CodeMod.Rename.DocumentChanges do
  defstruct [:uri, :edits, :rename_file]

  @type t :: %__MODULE__{
          uri: Lexical.uri(),
          edits: [Lexical.Document.Edit.t()],
          rename_file: {Lexical.uri(), Lexical.uri()} | nil
        }
  def new(uri, edits, rename_file \\ nil) do
    %__MODULE__{uri: uri, edits: edits, rename_file: rename_file}
  end
end
