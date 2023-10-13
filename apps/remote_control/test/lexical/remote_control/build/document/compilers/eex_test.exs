defmodule Lexical.RemoteControl.Build.Document.Compilers.EExTest do
  alias Lexical.Document
  alias Lexical.Plugin.V1.Diagnostic.Result
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.Build.CaptureServer
  alias Lexical.RemoteControl.Build.Document.Compilers
  alias Lexical.RemoteControl.Dispatch
  alias Lexical.RemoteControl.ModuleMappings

  use ExUnit.Case

  import Compilers.EEx
  import Lexical.Test.CodeSigil

  def with_capture_server(_) do
    start_supervised!(CaptureServer)
    start_supervised!(Dispatch)
    start_supervised!(ModuleMappings)
    :ok
  end

  def document_with_extension(extension) do
    Document.new("file:///file#{extension}", "", 0)
  end

  def document_with_content(content) do
    Document.new("file:///file.eex", content, 0)
  end

  setup_all do
    prev_compiler_options = Code.compiler_options()
    Build.State.set_compiler_options()

    on_exit(fn ->
      Code.compiler_options(prev_compiler_options)
    end)
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

  describe "eex_to_quoted/1" do
    setup [:with_capture_server]

    test "handles syntax errors" do
      {:error, [%Result{} = result]} =
        ~q[
        <%=
        ]t
        |> document_with_content()
        |> compile()

      # this assert is the best we can do; the error differs on different elixir versions
      assert result.message =~ "'%>'"
      assert {1, column} = result.position
      # The error's column differs on different elixir versions.
      assert column == 1 or column == 4
      assert result.severity == :error
      assert result.source == "EEx"
      assert result.uri
    end
  end

  describe "compile_quoted/2" do
    setup [:with_capture_server]

    test "handles unused variables" do
      assert {:ok, [%Result{} = result]} =
               ~q[
               <%= something = 6 %>
               ]
               |> document_with_content()
               |> compile()

      assert result.message =~ ~s["something" is unused]
      assert result.position in [1, {1, 5}]
      assert result.severity == :warning
      assert result.source == "EEx"
      assert result.uri =~ "file:///file.eex"
    end
  end

  describe "eval_quoted/2" do
    test "handles undefinied function" do
      document = document_with_content(~q[
        <%= IO.uts("thing") %>
      ])

      assert {:error, [%Result{} = result]} = compile(document)
      assert result.message =~ "function IO.uts/1 is undefined or private"
      assert result.position == {1, 8}
      assert result.severity == :error
      assert result.source == "EEx"
      assert result.uri =~ "file:///file.eex"
    end

    @tag :with_diagnostics
    test "handles undefinied variable" do
      document = document_with_content(~q[
        <%= thing %>
      ])

      assert {:error, [%Result{} = result]} = compile(document)

      if Features.with_diagnostics?() do
        assert result.message =~ "undefined variable \"thing\""
      else
        assert result.message =~ "undefined function thing/0"
      end

      assert result.position in [1, {1, 5}]
      assert result.severity == :error
      assert result.source == "EEx"
      assert result.uri =~ "file:///file.eex"
    end
  end
end
