defmodule Lexical.Protocol.ResponseTest do
  alias Lexical.Proto
  alias Lexical.Proto.Convert
  alias Lexical.Protocol.Types
  alias Lexical.SourceFile

  use ExUnit.Case

  def with_open_document(_) do
    source_file = """
    defmodule MyTest do
      def add(a, b), do: a + b
    end
    """

    file_uri = "file:///file.ex"
    {:ok, _} = start_supervised(SourceFile.Store)
    SourceFile.Store.open(file_uri, source_file, 1)

    {:ok, uri: file_uri}
  end

  describe "converting responses" do
    setup [:with_open_document]

    defmodule TextDocumentAndPosition do
      alias Lexical.Protocol.Types
      use Proto

      deftype text_document: Types.TextDocument.Identifier,
              placement: Types.Position
    end

    defmodule PositionContainer do
      use Proto

      defresponse optional(TextDocumentAndPosition)
    end

    test "positions are converted", %{uri: file_uri} do
      identifier = Types.TextDocument.Identifier.new(uri: file_uri)

      elixir_position = SourceFile.Position.new(2, 2)
      body = TextDocumentAndPosition.new(text_document: identifier, placement: elixir_position)
      response = PositionContainer.new(15, body)

      assert {:ok, lsp_response} = Convert.to_lsp(response)
      assert lsp_response.id == 15
      assert lsp_response.result.text_document == identifier
      assert %Types.Position{} = _position = lsp_response.result.placement
    end

    defmodule Locations do
      alias Lexical.Protocol.Types
      use Proto

      defresponse list_of(Types.Location)
    end

    test "locations are converted", %{uri: file_uri} do
      location =
        Types.Location.new(
          uri: file_uri,
          range:
            SourceFile.Range.new(
              SourceFile.Position.new(2, 3),
              SourceFile.Position.new(2, 5)
            )
        )

      response = Locations.new(5, [location])
      assert {:ok, lsp_response} = Convert.to_lsp(response)
      assert lsp_response.id == 5
      assert [%Types.Location{} = _lsp_location] = lsp_response.result
    end
  end
end
