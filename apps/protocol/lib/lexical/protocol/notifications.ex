defmodule Lexical.Protocol.Notifications do
  alias Lexical.Proto
  alias Lexical.Protocol.Types

  defmodule Initialized do
    use Proto
    defnotification "initialized"
  end

  defmodule Exit do
    use Proto

    defnotification "exit"
  end

  defmodule Cancel do
    use Proto

    defnotification "$/cancelRequest", id: integer()
  end

  defmodule DidOpen do
    use Proto

    defnotification "textDocument/didOpen", text_document: Types.TextDocument.Item
  end

  defmodule DidClose do
    use Proto

    defnotification "textDocument/didClose", text_document: Types.TextDocument.Identifier
  end

  defmodule DidChange do
    use Proto

    defnotification "textDocument/didChange",
      text_document: Types.TextDocument.Versioned.Identifier,
      content_changes:
        list_of(
          one_of([
            Types.TextDocument.ContentChangeEvent.TextDocumentContentChangeEvent,
            Types.TextDocument.ContentChangeEvent.TextDocumentContentChangeEvent1
          ])
        )
  end

  defmodule DidChangeConfiguration do
    use Proto

    defnotification "workspace/didChangeConfiguration", settings: map_of(any())
  end

  defmodule DidChangeWatchedFiles do
    use Proto

    defnotification "workspace/didChangeWatchedFiles", changes: list_of(Types.FileEvent)
  end

  defmodule DidSave do
    use Proto

    defnotification "textDocument/didSave", text_document: Types.TextDocument.Identifier
  end

  defmodule PublishDiagnostics do
    use Proto

    defnotification "textDocument/publishDiagnostics",
      uri: string(),
      version: optional(integer()),
      diagnostics: list_of(Types.Diagnostic)
  end

  defmodule LogMessage do
    use Proto
    require Types.Message.Type

    defnotification "window/logMessage",
      message: string(),
      type: Types.Message.Type

    for type <- [:error, :warning, :info, :log] do
      def unquote(type)(message) do
        new(message: message, type: Types.Message.Type.unquote(type)())
      end
    end
  end

  defmodule ShowMessage do
    use Proto
    require Types.Message.Type

    defnotification "window/showMessage",
      message: string(),
      type: Types.Message.Type

    for type <- [:error, :warning, :info, :log] do
      def unquote(type)(message) do
        new(message: message, type: Types.Message.Type.unquote(type)())
      end
    end
  end

  use Proto, decoders: :notifications
end
