defmodule Lexical.Test.DocumentSupport do
  alias Lexical.Document
  use ExUnit.CaseTemplate

  setup do
    {:ok, _store} = start_supervised(Document.Store)
    :ok
  end

  using do
    quote do
      alias Lexical.Document

      def open_file(file_uri \\ "file:///file.ex", contents) do
        with :ok <- Document.Store.open(file_uri, contents, 0),
             {:ok, doc} <- Document.Store.fetch(file_uri) do
          {:ok, file_uri, doc}
        end
      end
    end
  end
end
