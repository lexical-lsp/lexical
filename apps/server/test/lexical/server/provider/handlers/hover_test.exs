defmodule Lexical.Server.Provider.Handlers.HoverTest do
  alias Lexical.Document
  alias Lexical.Proto.Convert
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Types
  alias Lexical.Server
  alias Lexical.Server.Provider.Env
  alias Lexical.Server.Provider.Handlers

  import Lexical.Test.Protocol.Fixtures.LspProtocol
  import Lexical.RemoteControl.Api.Messages
  import Lexical.Test.Fixtures

  use ExUnit.Case, async: false

  setup_all do
    project = project()

    {:ok, _} = start_supervised(Document.Store)
    {:ok, _} = start_supervised({DynamicSupervisor, Server.Project.Supervisor.options()})
    {:ok, _} = start_supervised({Server.Project.Supervisor, project})

    :ok = Server.Project.Dispatch.register(project, [project_compiled()])
    assert_receive project_compiled(), 5000

    {:ok, project: project}
  end

  setup [:with_uri]

  defp with_uri(%{project: project, uri_for: file}) do
    path = file_path(project, Path.join("lib", file))
    %{uri: Document.Path.ensure_uri(path)}
  end

  defp with_uri(_) do
    :ok
  end

  def hover_request(path, line, char) do
    uri = Document.Path.ensure_uri(path)

    params = [
      text_document: [uri: uri],
      position: [line: line, character: char]
    ]

    with {:ok, _} <- Document.Store.open_temporary(uri),
         {:ok, req} <- build(Requests.Hover, params) do
      Convert.to_native(req)
    end
  end

  def handle(request, project) do
    Handlers.Hover.handle(request, %Env{project: project})
  end

  describe "module hover" do
    @describetag uri_for: "docs.ex"

    test "module with docs", %{project: project, uri: uri} do
      # alias Project.Docs.PublicModule
      #                    ^
      {:ok, request} = hover_request(uri, 64, 21)

      assert {:reply, %{result: %Types.Hover{contents: content}}} = handle(request, project)

      assert content.kind == :markdown

      assert content.value == """
             ### Project.Docs.PublicModule

             This module has docs.
             """
    end

    test "hidden module", %{project: project, uri: uri} do
      # alias Project.Docs.PrivateModule
      #                    ^
      {:ok, request} = hover_request(uri, 69, 21)

      assert {:reply, %{result: %Types.Hover{contents: content}}} = handle(request, project)

      assert content.kind == :markdown

      assert content.value == """
             ### Project.Docs.PrivateModule

             *This module is private.*
             """
    end

    test "undocumented module", %{project: project, uri: uri} do
      # alias Project.Docs.UndocumentedModule
      #                    ^
      {:ok, request} = hover_request(uri, 74, 21)

      assert {:reply, %{result: %Types.Hover{contents: content}}} = handle(request, project)

      assert content.kind == :markdown

      assert content.value == """
             ### Project.Docs.UndocumentedModule

             *This module is undocumented.*
             """
    end
  end

  @tag uri_for: "docs.ex"
  test "replies with nil result when there is nothing to hover", %{project: project, uri: uri} do
    # column well outside a reasonable range
    {:ok, request} = hover_request(uri, 0, 1_000)

    assert {:reply, %{result: nil}} = handle(request, project)
  end
end
