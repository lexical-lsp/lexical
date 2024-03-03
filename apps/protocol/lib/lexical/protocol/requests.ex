defmodule Lexical.Protocol.Requests do
  alias Lexical.Proto
  alias Lexical.Protocol.Responses
  alias Lexical.Protocol.Types

  # Client -> Server request
  defmodule Initialize do
    use Proto

    defrequest "initialize", Types.Initialize.Params
  end

  defmodule Cancel do
    use Proto

    defrequest "$/cancelRequest", Types.Cancel.Params
  end

  defmodule Shutdown do
    use Proto

    defrequest "shutdown"
  end

  defmodule FindReferences do
    use Proto

    defrequest "textDocument/references", Types.Reference.Params
  end

  defmodule GoToDefinition do
    use Proto

    defrequest "textDocument/definition", Types.Definition.Params
  end

  defmodule CreateWorkDoneProgress do
    use Proto

    defrequest "window/workDoneProgress/create", Types.WorkDone.Progress.Create.Params
  end

  defmodule Formatting do
    use Proto

    defrequest "textDocument/formatting", Types.Document.Formatting.Params
  end

  defmodule CodeAction do
    use Proto

    defrequest "textDocument/codeAction", Types.CodeAction.Params
  end

  defmodule CodeLens do
    use Proto

    defrequest "textDocument/codeLens", Types.CodeLens.Params
  end

  defmodule Completion do
    use Proto

    defrequest "textDocument/completion", Types.Completion.Params
  end

  defmodule Hover do
    use Proto

    defrequest "textDocument/hover", Types.Hover.Params
  end

  defmodule ExecuteCommand do
    use Proto

    defrequest "workspace/executeCommand", Types.ExecuteCommand.Params
  end

  defmodule DocumentSymbols do
    use Proto

    defrequest "textDocument/documentSymbol", Types.Document.Symbol.Params
  end

  defmodule WorkspaceSymbol do
    use Proto

    defrequest "workspace/symbol", Types.Workspace.Symbol.Params
  end

  defmodule PrepareRename do
    use Proto

    defrequest "textDocument/prepareRename", Types.PrepareRename.Params
  end

  defmodule Rename do
    use Proto

    defrequest "textDocument/rename", Types.Rename.Params
  end

  # Server -> Client requests

  defmodule RegisterCapability do
    use Proto

    server_request "client/registerCapability", Types.Registration.Params, Responses.Empty
  end

  defmodule ShowMessageRequest do
    use Proto

    server_request "window/showMessageRequest",
                   Types.ShowMessageRequest.Params,
                   Responses.ShowMessage
  end

  defmodule CodeLensRefresh do
    use Proto

    server_request "workspace/codeLens/refresh", Responses.Empty
  end

  use Proto, decoders: :requests
end
