defmodule Lexical.Protocol.Requests do
  alias Lexical.Proto
  alias Lexical.Protocol.LspTypes
  alias Lexical.Protocol.Types

  # Client -> Server request
  defmodule Initialize do
    use Proto

    defrequest "initialize",
      capabilities: optional(Types.ClientCapabilities),
      client_info: optional(LspTypes.ClientInfo),
      initialization_options: optional(any()),
      locale: optional(string()),
      process_id: optional(integer()),
      root_path: optional(string()),
      root_uri: optional(uri()),
      trace: optional(Types.TraceValues),
      workspace_folders: optional(list_of(Types.Workspace.Folder))
  end

  defmodule Cancel do
    use Proto

    defrequest "$/cancelRequest", id: one_of([string(), integer()])
  end

  defmodule Shutdown do
    use Proto

    defrequest "shutdown", []
  end

  defmodule FindReferences do
    use Proto

    defrequest "textDocument/references",
      position: Types.Position,
      text_document: Types.TextDocument.Identifier
  end

  defmodule GoToDefinition do
    use Proto

    defrequest "textDocument/definition",
      text_document: Types.TextDocument.Identifier,
      position: Types.Position
  end

  defmodule Formatting do
    use Proto

    defrequest "textDocument/formatting",
      options: Types.Formatting.Options,
      text_document: Types.TextDocument.Identifier
  end

  defmodule CodeAction do
    use Proto

    defrequest "textDocument/codeAction",
      context: Types.CodeAction.Context,
      range: Types.Range,
      text_document: Types.TextDocument.Identifier
  end

  defmodule Completion do
    use Proto

    defrequest "textDocument/completion",
      text_document: Types.TextDocument.Identifier,
      position: Types.Position,
      context: Types.Completion.Context
  end

  # Server -> Client requests

  defmodule RegisterCapability do
    use Proto

    defrequest "client/registerCapability",
      registrations: optional(list_of(LspTypes.Registration))
  end

  use Proto, decoders: :requests
end
