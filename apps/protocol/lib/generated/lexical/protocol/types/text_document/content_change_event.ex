# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.TextDocument.ContentChangeEvent do
  alias Lexical.Protocol.Proto
  alias Lexical.Protocol.Types
  alias __MODULE__, as: Parent

  defmodule TextDocumentContentChangeEvent do
    use Proto
    deftype range: Types.Range, range_length: optional(integer()), text: string()
  end

  defmodule TextDocumentContentChangeEvent1 do
    use Proto
    deftype text: string()
  end

  use Proto
  defalias one_of([Parent.TextDocumentContentChangeEvent, Parent.TextDocumentContentChangeEvent1])
end
