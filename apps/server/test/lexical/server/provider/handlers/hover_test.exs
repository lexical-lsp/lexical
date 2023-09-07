defmodule Lexical.Server.Provider.Handlers.HoverTest do
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Proto.Convert
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Types
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.Server
  alias Lexical.Server.Provider.Env
  alias Lexical.Server.Provider.Handlers
  alias Lexical.Test.Fixtures
  alias Lexical.Test.Protocol.Fixtures.LspProtocol

  import Lexical.Test.CodeSigil
  import Lexical.Test.CursorSupport

  require Messages

  use ExUnit.Case, async: false

  setup_all do
    project = Fixtures.project()

    {:ok, _} = start_supervised(Document.Store)
    {:ok, _} = start_supervised({DynamicSupervisor, Server.Project.Supervisor.options()})
    {:ok, _} = start_supervised({Server.Project.Supervisor, project})

    :ok = RemoteControl.Api.register_listener(project, self(), [Messages.project_compiled()])
    assert_receive Messages.project_compiled(), 5000

    {:ok, project: project}
  end

  # compiles and writes beam files in the given project
  defp with_compiled_in(project, code, fun) do
    tmp_dir = Fixtures.file_path(project, "lib/tmp")

    tmp_path =
      tmp_dir
      |> Path.join("tmp_#{rand_hex(10)}.ex")

    File.mkdir_p!(tmp_dir)

    with_tmp_file(tmp_path, code, fn ->
      {:ok, compile_path} =
        RemoteControl.Mix.in_project(project, fn _ ->
          Mix.Project.compile_path()
        end)

      {:ok, modules, _} =
        RemoteControl.call(project, Kernel.ParallelCompiler, :compile_to_path, [
          [tmp_path],
          compile_path
        ])

      try do
        fun.()
      after
        for module <- modules do
          path = RemoteControl.call(project, :code, :which, [module])
          RemoteControl.call(project, :code, :delete, [module])
          File.rm!(path)
        end
      end
    end)
  end

  defp rand_hex(n_bytes) do
    n_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.hex_encode32()
  end

  defp with_tmp_file(file, content, fun) do
    File.write!(file, content)
    fun.()
  after
    File.rm_rf!(file)
  end

  describe "module hover" do
    test "replies with public module doc", %{project: project} do
      code = ~q[
        defmodule HoverWithDoc do
          @moduledoc """
          This module has a moduledoc.
          """
        end
      ]

      with_compiled_in(project, code, fn ->
        assert {:reply, %{result: %Types.Hover{} = result}} = hover(project, "|HoverWithDoc")
        assert result.contents.kind == :markdown

        assert result.contents.value == """
               ### HoverWithDoc

               This module has a moduledoc.
               """
      end)
    end

    test "notes private modules", %{project: project} do
      code = ~q[
        defmodule HoverPrivate do
          @moduledoc false
        end
      ]

      with_compiled_in(project, code, fn ->
        assert {:reply, %{result: %Types.Hover{} = result}} = hover(project, "|HoverPrivate")
        assert result.contents.kind == :markdown

        assert result.contents.value == """
               ### HoverPrivate

               *This module is private.*
               """
      end)
    end

    test "notes modules without docs", %{project: project} do
      code = ~q[
        defmodule HoverNoDocs do
        end
      ]

      with_compiled_in(project, code, fn ->
        assert {:reply, %{result: %Types.Hover{} = result}} = hover(project, "|HoverNoDocs")
        assert result.contents.kind == :markdown

        assert result.contents.value == """
               ### HoverNoDocs

               *This module is undocumented.*
               """
      end)
    end
  end

  defp hover(project, code) do
    with {position, code} <- pop_position(code),
         {:ok, document} <- document_with_content(project, code),
         {:ok, request} <- hover_request(document.uri, position) do
      Handlers.Hover.handle(request, %Env{project: project})
    end
  end

  defp pop_position(code) do
    {line, character} = cursor_position(code)
    {Position.new(line, character), strip_cursor(code)}
  end

  defp document_with_content(project, content) do
    uri =
      project
      |> Fixtures.file_path(Path.join("lib", "my_doc.ex"))
      |> Document.Path.ensure_uri()

    case Document.Store.open(uri, content, 1) do
      :ok ->
        Document.Store.fetch(uri)

      {:error, :already_open} ->
        Document.Store.close(uri)
        document_with_content(project, content)

      error ->
        error
    end
  end

  defp hover_request(path, %Position{} = position) do
    hover_request(path, position.line, position.character)
  end

  defp hover_request(path, line, char) do
    uri = Document.Path.ensure_uri(path)

    params = [
      text_document: [uri: uri],
      position: [line: line, character: char]
    ]

    with {:ok, _} <- Document.Store.open_temporary(uri),
         {:ok, req} <- LspProtocol.build(Requests.Hover, params) do
      Convert.to_native(req)
    end
  end
end
