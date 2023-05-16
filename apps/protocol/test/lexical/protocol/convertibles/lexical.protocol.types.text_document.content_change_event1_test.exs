defmodule Lexical.Protocol.Convertibles.ContentChangeEvent.TextDocumentContentChangeEvent1Test do
  alias Lexical.Protocol.Types.TextDocument.ContentChangeEvent.TextDocumentContentChangeEvent1,
    as: TextOnlyEvent

  use Lexical.Test.Protocol.ConvertibleSupport

  describe "to_lsp/2)" do
    setup [:with_an_open_file]

    test "is a no-op", %{uri: uri} do
      native_text_edit = TextOnlyEvent.new(text: "hi")
      assert {:ok, ^native_text_edit} = to_lsp(native_text_edit, uri)
    end
  end

  describe "to_native/2" do
    setup [:with_an_open_file]

    test "converts to a single replace edit", %{uri: uri} do
      replacement_text = "This is the replacement text"
      event = TextOnlyEvent.new(text: replacement_text)
      {:ok, %Document.Edit{} = converted} = to_native(event, uri)

      assert converted.text == replacement_text
      assert converted.range == nil
    end
  end
end
