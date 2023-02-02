# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.Notebook.Document.Sync.Options do
  alias Lexical.Protocol.Proto
  alias Lexical.Protocol.Types
  alias __MODULE__, as: Parent

  defmodule Cells do
    use Proto
    deftype language: string()
  end

  defmodule Cells1 do
    use Proto
    deftype language: string()
  end

  defmodule NotebookSelector do
    use Proto

    deftype cells: optional(list_of(Parent.Cells)),
            notebook: one_of([string(), Types.Notebook.Document.Filter])
  end

  defmodule NotebookSelector1 do
    use Proto

    deftype cells: list_of(Parent.Cells1),
            notebook: optional(one_of([string(), Types.Notebook.Document.Filter]))
  end

  use Proto

  deftype notebook_selector: list_of(one_of([Parent.NotebookSelector, Parent.NotebookSelector1])),
          save: optional(boolean())
end
