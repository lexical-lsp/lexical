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

    defnotification "$/cancelRequest", Types.Cancel.Params
  end

  defmodule DidOpen do
    use Proto

    defnotification "textDocument/didOpen", Types.DidOpenTextDocument.Params
  end

  defmodule DidClose do
    use Proto

    defnotification "textDocument/didClose", Types.DidCloseTextDocument.Params
  end

  defmodule DidChange do
    use Proto

    defnotification "textDocument/didChange", Types.DidChangeTextDocument.Params
  end

  defmodule DidChangeConfiguration do
    use Proto

    defnotification "workspace/didChangeConfiguration", Types.DidChangeConfiguration.Params
  end

  defmodule DidChangeWatchedFiles do
    use Proto

    defnotification "workspace/didChangeWatchedFiles", Types.DidChangeWatchedFiles.Params
  end

  defmodule DidSave do
    use Proto

    defnotification "textDocument/didSave", Types.DidSaveTextDocument.Params
  end

  defmodule PublishDiagnostics do
    use Proto

    defnotification "textDocument/publishDiagnostics", Types.PublishDiagnostics.Params
  end

  defmodule LogMessage do
    use Proto
    require Types.Message.Type

    defnotification "window/logMessage", Types.LogMessage.Params

    for type <- [:error, :warning, :info, :log] do
      def unquote(type)(message) do
        new(message: message, type: Types.Message.Type.unquote(type)())
      end
    end
  end

  defmodule ShowMessage do
    use Proto
    require Types.Message.Type

    defnotification "window/showMessage", Types.ShowMessage.Params

    for type <- [:error, :warning, :info, :log] do
      def unquote(type)(message) do
        new(message: message, type: Types.Message.Type.unquote(type)())
      end
    end
  end

  defmodule Progress do
    use Proto

    defnotification "$/progress", Types.Progress.Params
  end

  use Proto, decoders: :notifications
end
