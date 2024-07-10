defmodule Lexical.Server.Provider.Handlers.CodeLensTest do
  alias Lexical.Document
  alias Lexical.Project
  alias Lexical.Proto.Convert
  alias Lexical.Protocol.Requests.CodeLens
  alias Lexical.Protocol.Types
  alias Lexical.RemoteControl
  alias Lexical.Server
  alias Lexical.Server.Provider.Handlers

  import Lexical.Test.Protocol.Fixtures.LspProtocol
  import Lexical.RemoteControl.Api.Messages
  import Lexical.Test.Fixtures
  import Lexical.Test.RangeSupport

  use ExUnit.Case, async: false
  use Patch

  setup_all do
    start_supervised(Document.Store)
    project = project(:umbrella)

    start_supervised!({DynamicSupervisor, Server.Project.Supervisor.options()})
    start_supervised!({Server.Project.Supervisor, project})

    RemoteControl.Api.register_listener(project, self(), [project_compiled()])
    RemoteControl.Api.schedule_compile(project, true)

    assert_receive project_compiled(), 5000

    {:ok, project: project}
  end

  defp with_indexing_enabled(_) do
    patch(Lexical.RemoteControl.Api, :index_running?, false)
    :ok
  end

  defp with_mix_exs(%{project: project}) do
    path = Project.mix_exs_path(project)
    %{uri: Document.Path.ensure_uri(path)}
  end

  def build_request(path) do
    uri = Document.Path.ensure_uri(path)

    params = [
      text_document: [uri: uri]
    ]

    with {:ok, _} <- Document.Store.open_temporary(uri),
         {:ok, req} <- build(CodeLens, params) do
      Convert.to_native(req)
    end
  end

  def handle(request, project) do
    config = Server.Configuration.new(project: project)
    Handlers.CodeLens.handle(request, config)
  end

  describe "code lens for mix.exs" do
    setup [:with_mix_exs, :with_indexing_enabled]

    test "emits a code lens at the project definition", %{project: project, uri: referenced_uri} do
      mix_exs_path = Document.Path.ensure_path(referenced_uri)
      mix_exs = File.read!(mix_exs_path)

      {:ok, request} = build_request(mix_exs_path)
      {:reply, %{result: lenses}} = handle(request, project)

      assert [%Types.CodeLens{} = code_lens] = lenses

      assert extract(mix_exs, code_lens.range) =~ "def project"
      assert code_lens.command == Handlers.Commands.reindex_command(project)
    end

    test "does not emit a code lens for a project file", %{project: project} do
      {:ok, request} =
        project
        |> Project.project_path()
        |> Path.join("apps/first/lib/umbrella/first.ex")
        |> build_request()

      assert {:reply, %{result: []}} = handle(request, project)
    end

    test "does not emite a code lens for an umbrella app's mix.exs", %{project: project} do
      {:ok, request} =
        project
        |> Project.project_path()
        |> Path.join("apps/first/mix.exs")
        |> build_request()

      assert {:reply, %{result: []}} = handle(request, project)
    end
  end
end
