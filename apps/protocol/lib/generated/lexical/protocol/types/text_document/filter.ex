# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.TextDocument.Filter do
  alias Lexical.Proto
  alias __MODULE__, as: Parent

  defmodule TextDocumentFilter do
    use Proto
    deftype language: string(), pattern: optional(string()), scheme: optional(string())
  end

  defmodule TextDocumentFilter1 do
    use Proto
    deftype language: optional(string()), pattern: optional(string()), scheme: string()
  end

  defmodule TextDocumentFilter2 do
    use Proto
    deftype language: optional(string()), pattern: string(), scheme: optional(string())
  end

  use Proto

  defalias one_of([
             Parent.TextDocumentFilter,
             Parent.TextDocumentFilter1,
             Parent.TextDocumentFilter2
           ])
end
