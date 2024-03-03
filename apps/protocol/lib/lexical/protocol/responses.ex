defmodule Lexical.Protocol.Responses do
  alias Lexical.Proto
  alias Lexical.Proto.Typespecs
  alias Lexical.Protocol.Types

  defmodule Empty do
    use Proto

    defresponse optional(Types.LSPObject)
  end

  defmodule InitializeResult do
    use Proto

    defresponse Types.Initialize.Result
  end

  defmodule FindReferences do
    use Proto

    defresponse optional(list_of(Types.Location))
  end

  defmodule GoToDefinition do
    use Proto

    defresponse optional(Types.Location)
  end

  defmodule Formatting do
    use Proto

    defresponse optional(list_of(Types.TextEdit))
  end

  defmodule CodeAction do
    use Proto

    defresponse optional(list_of(Types.CodeAction))
  end

  defmodule CodeLens do
    use Proto
    defresponse optional(list_of(Types.CodeLens))
  end

  defmodule Completion do
    use Proto

    defresponse optional(list_of(one_of([list_of(Types.Completion.Item), Types.Completion.List])))
  end

  defmodule DocumentSymbols do
    use Proto

    defresponse optional(list_of(Types.Document.Symbol))
  end

  defmodule WorkspaceSymbol do
    use Proto

    defresponse optional(list_of(Types.Workspace.Symbol))
  end

  defmodule Shutdown do
    use Proto
    # yeah, this is odd... it has no params
    defresponse []
  end

  defmodule Hover do
    use Proto

    defresponse optional(Types.Hover)
  end

  defmodule ExecuteCommand do
    use Proto

    defresponse optional(any())
  end

  # Client -> Server responses

  defmodule ShowMessage do
    use Proto
    defresponse optional(Types.Message.ActionItem)
  end

  defmodule PrepareRename do
    use Proto

    defresponse Types.PrepareRenameResult
  end

  defmodule Rename do
    use Proto

    defresponse optional(Types.Workspace.Edit)
  end

  use Typespecs, for: :responses
end
