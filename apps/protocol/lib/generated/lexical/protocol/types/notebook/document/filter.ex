# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.Notebook.Document.Filter do
  alias Lexical.Proto

  defmodule NotebookDocumentFilter do
    use Proto
    deftype notebook_type: string(), pattern: optional(string()), scheme: optional(string())
  end

  defmodule NotebookDocumentFilter1 do
    use Proto
    deftype notebook_type: optional(string()), pattern: optional(string()), scheme: string()
  end

  defmodule NotebookDocumentFilter2 do
    use Proto
    deftype notebook_type: optional(string()), pattern: string(), scheme: optional(string())
  end

  use Proto

  defalias one_of([
             Lexical.Protocol.Types.Notebook.Document.Filter.NotebookDocumentFilter,
             Lexical.Protocol.Types.Notebook.Document.Filter.NotebookDocumentFilter1,
             Lexical.Protocol.Types.Notebook.Document.Filter.NotebookDocumentFilter2
           ])
end
