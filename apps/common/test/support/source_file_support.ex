defmodule Lexical.Test.SourceFileSupport do
  alias Lexical.SourceFile
  use ExUnit.CaseTemplate

  setup do
    {:ok, _store} = start_supervised(SourceFile.Store)
    :ok
  end

  using do
    quote do
      alias Lexical.SourceFile

      def open_file(file_uri \\ "file:///file.ex", contents) do
        with :ok <- SourceFile.Store.open(file_uri, contents, 0),
             {:ok, doc} <- SourceFile.Store.fetch(file_uri) do
          {:ok, file_uri, doc}
        end
      end
    end
  end
end
