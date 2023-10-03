defmodule Lexical.RemoteControl.Build.Document.Compilers.HeexTest do
  alias Lexical.Document
  alias Lexical.Plugin.V1.Diagnostic.Result
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.Build.CaptureServer
  alias Lexical.RemoteControl.Build.Document.Compilers
  alias Lexical.RemoteControl.Dispatch
  alias Lexical.RemoteControl.ModuleMappings

  import Lexical.Test.CodeSigil
  import Compilers.HEEx, only: [compile: 1]

  use ExUnit.Case

  def with_capture_server(_) do
    start_supervised!(CaptureServer)
    start_supervised!(Dispatch)
    start_supervised!(ModuleMappings)
    :ok
  end

  def document_with_content(content) do
    Document.new("file:///file.heex", content, 0)
  end

  setup_all do
    Build.State.set_compiler_options()
  end

  describe "compile/1" do
    setup [:with_capture_server]

    test "handles valid HEEx content" do
      document = document_with_content(~q[
        <div>thing</div>
      ])
      assert {:ok, []} = compile(document)
    end

    test "ignore undefinied assigns" do
      document = document_with_content(~q[
        <div><%= @thing %></div>
      ])

      assert {:error, []} = compile(document)
    end

    test "returns error when there are unclosed tags" do
      document = document_with_content(~q[
        <div>thing
      ])
      assert {:error, [%Result{} = result]} = compile(document)

      assert result.message =~
               "end of template reached without closing tag for <div>\n  |\n1 | <div>thing\n  | ^"

      assert result.position == {1, 1}
      assert result.severity == :error
      assert result.source == "HEEx"
      assert result.uri =~ "file:///file.heex"
    end

    test "returns error when HEEx syntax is invalid" do
      document = document_with_content(~q[
        <span id=@id}></span>
      ])

      assert {:error, [%Result{} = result]} = compile(document)

      assert result.message =~ "invalid attribute value after `=`. "
      assert result.position == {1, 10}
      assert result.severity == :error
      assert result.source == "HEEx"
      assert result.uri =~ "file:///file.heex"
    end

    test "handles EEx syntax error" do
      document = document_with_content(~q[
        <%= IO.
      ])
      assert {:error, [%Result{} = result]} = compile(document)

      assert result.message =~ "'%>'"
      assert result.source == "EEx"
    end
  end
end
