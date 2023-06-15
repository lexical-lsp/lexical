defmodule LexicalCredoTest do
  alias Lexical.Plugin.V1.Diagnostic.Result
  alias Lexical.Document

  import LexicalCredo
  use ExUnit.Case

  def doc(contents) do
    Document.new("file:///file.ex", contents, 1)
  end

  test "reports errors on documents" do
    has_inspect =
      """
      defmodule Bad do
        def test do
          IO.inspect("hello")
        end
      end
      """
      |> doc()
      |> handle()

    assert {:ok, [%Result{} = result]} = has_inspect
    assert result.position == {3, 5}
    assert result.message == "There should be no calls to IO.inspect/1."
    assert String.ends_with?(result.uri, "/file.ex")
    assert result.severity == :error
    assert result.source == "Credo"
  end
end
