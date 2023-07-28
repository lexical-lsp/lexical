defmodule Lexical.RemoteControl.Build.Document.Compilers.EExTest do
  alias Lexical.Document
  alias Lexical.Plugin.V1.Diagnostic.Result
  alias Lexical.RemoteControl.Build.CaptureServer
  alias Lexical.RemoteControl.Build.Document.Compilers
  alias Lexical.RemoteControl.ModuleMappings

  use ExUnit.Case

  import Compilers.EEx
  import Lexical.Test.CodeSigil

  def with_capture_server(_) do
    start_supervised!(CaptureServer)
    start_supervised!(ModuleMappings)
    :ok
  end

  def document_with_extension(extension) do
    Document.new("file:///file#{extension}", "", 0)
  end

  def document_with_content(content) do
    Document.new("file:///file.eex", content, 0)
  end

  describe "recognizes?/1" do
    test "is true for .eex files" do
      assert recognizes?(document_with_extension(".eex"))
      assert recognizes?(document_with_extension(".html.eex"))
      assert recognizes?(document_with_extension(".js.eex"))
    end

    test "is false for elixir files" do
      refute recognizes?(document_with_extension(".ex"))
      refute recognizes?(document_with_extension(".exs"))
    end

    test "is false for other file types" do
      refute recognizes?(document_with_extension(".html"))
      refute recognizes?(document_with_extension(".js"))
      refute recognizes?(document_with_extension(".lock"))
    end
  end

  describe "compile/1" do
    setup [:with_capture_server]

    test "handles syntax errors" do
      {:error, [%Result{} = result]} =
        ~q[
        <%=
        ]
        |> document_with_content()
        |> compile()

      assert result.message =~ "missing token '%>'"
      assert result.position == {2, 1}
      assert result.severity == :error
      assert result.source == "EEx"
      assert result.uri
    end

    test "handles unused variables" do
      assert {:ok, [%Result{} = result]} =
               ~q[
               <%= something = 6 %>
               ]
               |> document_with_content()
               |> compile()

      assert result.message =~ ~s["something" is unused]
      assert result.position == 1
      assert result.severity == :warning
      assert result.source == "EEx"
      assert result.uri =~ "file:///file.eex"
    end
  end
end
