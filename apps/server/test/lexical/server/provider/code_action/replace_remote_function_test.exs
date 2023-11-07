defmodule Lexical.Server.Provider.CodeAction.ReplaceRemoteFunctionTest do
  alias Lexical.Document
  alias Lexical.Proto.Convert
  alias Lexical.Protocol.Requests.CodeAction
  alias Lexical.RemoteControl
  alias Lexical.Server
  alias Lexical.Server.Provider.Env
  alias Lexical.Server.Provider.Handlers

  import Lexical.Test.Protocol.Fixtures.LspProtocol
  import Lexical.RemoteControl.Api.Messages
  import Lexical.Test.Fixtures

  use ExUnit.Case, async: false

  setup_all do
    start_supervised(Document.Store)
    project = project(:code_actions)

    {:ok, _} = start_supervised({DynamicSupervisor, Server.Project.Supervisor.options()})

    {:ok, _} = start_supervised({Server.Project.Supervisor, project})

    RemoteControl.Api.register_listener(project, self(), [project_compiled()])
    RemoteControl.Api.schedule_compile(project, true)

    assert_receive project_compiled(), 5000

    path = file_path(project, Path.join("lib", "main.ex"))

    {:ok, project: project, uri: Document.Path.ensure_uri(path)}
  end

  def build_request(path, line, char) do
    uri = Document.Path.ensure_uri(path)

    diagnostics = [
      [
        message: diagnostic_message(),
        range: [end: [line: line + 1, character: 1], start: [line: line, character: char]]
      ]
    ]

    params = [
      context: [diagnostics: diagnostics],
      range: [],
      text_document: [uri: uri]
    ]

    with {:ok, _} <- Document.Store.open_temporary(uri),
         {:ok, req} <- build(CodeAction, params) do
      Convert.to_native(req)
    end
  end

  defp diagnostic_message do
    """
    Remote.A.B.C.fun/0 is undefined or private. Did you mean:
          * func/0
    """
  end

  def handle(request, project) do
    Handlers.CodeAction.handle(request, %Env{project: project})
  end

  test "replace remote function call", %{project: project, uri: uri} do
    {:ok, request} = build_request(uri, 5, 4)

    {:reply, %{result: [code_action]}} = handle(request, project)

    assert code_action.title == "Rename to func"

    assert %{edit: %{changes: %{^uri => %{edits: [edit]}}}} = code_action

    # Remote.A.B.C.fun()
    assert edit.range.start.line == 6
    assert edit.range.start.character == 18
    assert edit.range.end.line == 6
    assert edit.range.end.character == 21
    assert edit.text == "func"
  end

  test "replace only properly aliased remote function call", %{project: project, uri: uri} do
    {:ok, request} = build_request(uri, 6, 4)

    {:reply, %{result: [code_action]}} = handle(request, project)

    assert code_action.title == "Rename to func"

    assert %{edit: %{changes: %{^uri => %{edits: edits}}}} = code_action

    assert [edit_1, edit_2] =
             Enum.sort(edits, &(&1.range.start.character <= &2.range.start.character))

    # JustRemote.C.fun()
    assert edit_1.range.start.line == 7
    assert edit_1.range.start.character == 19
    assert edit_1.range.end.line == 7
    assert edit_1.range.end.character == 22
    assert edit_1.text == "func"

    # C.fun()
    assert edit_2.range.start.line == 7
    assert edit_2.range.start.character == 39
    assert edit_2.range.end.line == 7
    assert edit_2.range.end.character == 42
    assert edit_2.text == "func"
  end

  test "replace remote function capture", %{project: project, uri: uri} do
    {:ok, request} = build_request(uri, 10, 4)

    {:reply, %{result: [code_action]}} = handle(request, project)

    assert code_action.title == "Rename to func"

    assert %{edit: %{changes: %{^uri => %{edits: edits}}}} = code_action

    assert [edit_1, edit_2, edit_3] =
             Enum.sort(edits, &(&1.range.start.character <= &2.range.start.character))

    # &Remote.A.B.C.fun/0
    assert edit_1.range.start.line == 11
    assert edit_1.range.start.character == 20
    assert edit_1.range.end.line == 11
    assert edit_1.range.end.character == 23
    assert edit_1.text == "func"

    # &JustRemote.C.fun/0
    assert edit_2.range.start.line == 11
    assert edit_2.range.start.character == 41
    assert edit_2.range.end.line == 11
    assert edit_2.range.end.character == 44
    assert edit_2.text == "func"

    # &C.fun/0
    assert edit_3.range.start.line == 11
    assert edit_3.range.start.character == 63
    assert edit_3.range.end.line == 11
    assert edit_3.range.end.character == 66
    assert edit_3.text == "func"
  end
end
