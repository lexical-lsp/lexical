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

  defmodule Completion do
    use Proto

    defrequest "textDocument/completion", Types.Completion.Params
  end

  defmodule Hover do
    use Proto

    defrequest "textDocument/hover", Types.Hover.Params
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

  use Proto, decoders: :requests
end
