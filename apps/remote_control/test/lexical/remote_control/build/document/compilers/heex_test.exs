defmodule Lexical.RemoteControl.Build.Document.Compilers.HeexTest do
  alias Lexical.Document
  alias Lexical.Plugin.V1.Diagnostic.Result
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.Build.CaptureServer
  alias Lexical.RemoteControl.Build.Document.Compilers
  alias Lexical.RemoteControl.ModuleMappings
  alias Lexical.RemoteControl.ProjectNodeSupervisor

  import Lexical.Test.Fixtures
  import Messages
  import Lexical.Test.CodeSigil

  use ExUnit.Case

  def with_capture_server(_) do
    start_supervised!(CaptureServer)
    start_supervised!(ModuleMappings)
    :ok
  end

  def with_liveview_project(_) do
    fixture_dir = Path.join(fixtures_path(), "live_demo")
    project = Project.new("file://#{fixture_dir}")

    {:ok, _} = start_supervised({ProjectNodeSupervisor, project})
    {:ok, _, _} = RemoteControl.start_link(project, self())
    Build.schedule_compile(project, true)

    assert_receive project_compiled(status: :success), 10_000

    {:ok, %{project: project}}
  end

  defp compile(project, document) do
    RemoteControl.call(project, Compilers.HEEx, :compile, [document])
  end

  def document_with_content(content) do
    Document.new("file:///file.heex", content, 0)
  end

  setup_all [:with_liveview_project, :with_capture_server]

  describe "compile/1" do
    test "handles valid EEx content", %{project: project} do
      document = document_with_content(~q[
        <%= "thing" %>
      ])

      assert {:ok, []} = compile(project, document)
    end

    test "handles EEx syntax error", %{project: project} do
      document = document_with_content(~q[
        <%= IO.
      ])
      assert {:error, [%Result{} = result]} = compile(project, document)

      assert result.message =~ "'%>'"
      assert result.source == "HEEx"
    end

    test "handles unused error", %{project: project} do
      document = document_with_content(~q[
      <div>
        <%= something = 1 %>
      </div>
      ])

      assert {:ok, [%Result{} = result]} = compile(project, document)

      assert result.message == "variable \"something\" is unused"
      assert result.position == {2, 7}
      assert result.severity == :warning
      assert result.source == "HEEx"
      assert result.uri == "file:///file.heex"
    end

    test "handles undefinied function", %{project: project} do
      document = document_with_content(~q[
        <%= IO.uts("thing") %>
      ])

      assert {:error, [%Result{} = result]} = compile(project, document)
      assert result.message =~ "function IO.uts/1 is undefined or private"
      assert result.position == {1, 8}
      assert result.severity == :error
      assert result.source == "HEEx"
      assert result.uri =~ "file:///file.heex"
    end

    @tag :with_diagnostics

    test "handles undefinied variable", %{project: project} do
      document = document_with_content(~q[
        <%= thing %>
      ])

      assert {:error, [%Result{} = result]} = compile(project, document)

      assert result.message =~ "undefined variable \"thing\""
      assert result.position == {1, 5}
      assert result.severity == :error
      assert result.source == "HEEx"
      assert result.uri =~ "file:///file.heex"
    end

    test "ignore undefinied assigns", %{project: project} do
      document = document_with_content(~q[
        <div><%= @thing %></div>
      ])

      assert {:error, []} = compile(project, document)
    end

    test "handles valid HEEx content", %{project: project} do
      document = document_with_content(~q[
        <div>thing</div>
      ])
      assert {:ok, []} = compile(project, document)
    end

    test "handles unclosed tags", %{project: project} do
      document = document_with_content(~q[
        <div>thing
      ])
      assert {:error, [%Result{} = result]} = compile(project, document)

      assert result.message =~
               "end of template reached without closing tag for <div>\n  |\n1 | <div>thing\n  | ^"

      assert result.position == {1, 1}
      assert result.severity == :error
      assert result.source == "HEEx"
      assert result.uri =~ "file:///file.heex"
    end

    test "handles invalid HEEx syntax", %{project: project} do
      document = document_with_content(~q[
        <span id=@id}></span>
      ])

      assert {:error, [%Result{} = result]} = compile(project, document)

      assert result.message =~ "invalid attribute value after `=`. "
      assert result.position == {1, 10}
      assert result.severity == :error
      assert result.source == "HEEx"
      assert result.uri =~ "file:///file.heex"
    end
  end

  describe "function components" do
    @tag :skip
    test "handles undefined function component", %{project: project} do
      path = "lib/simple_live.html.heex"
      content = ~q[
       <.greets_world name={@name} />
      ]
      document = Document.new(path, content, 0)

      assert {:error, [error]} = compile(project, document)
      assert error.message =~ "undefined function \"greets_world\""
    end
  end
end
