defmodule Lexical.Server.Provider.Handlers.CodeLensTest do
  alias Lexical.Document
  alias Lexical.Proto.Convert
  alias Lexical.Protocol.Requests.CodeLens
  alias Lexical.Protocol.Types
  alias Lexical.RemoteControl
  alias Lexical.Server
  alias Lexical.Server.Provider.Env
  alias Lexical.Server.Provider.Handlers

  import Lexical.Test.Protocol.Fixtures.LspProtocol
  import Lexical.RemoteControl.Api.Messages
  import Lexical.Test.Fixtures
  import Lexical.Test.RangeSupport

  use ExUnit.Case, async: false

  setup_all do
    start_supervised(Document.Store)
    project = project(:navigations)

    {:ok, _} = start_supervised({DynamicSupervisor, Server.Project.Supervisor.options()})

    {:ok, _} = start_supervised({Server.Project.Supervisor, project})

    RemoteControl.Api.register_listener(project, self(), [project_compiled()])
    RemoteControl.Api.schedule_compile(project, true)

    assert_receive project_compiled(), 5000

    {:ok, project: project}
  end

  defp with_mix_exs(%{project: project}) do
    path = file_path(project, "mix.exs")
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
    Handlers.CodeLens.handle(request, %Env{project: project})
  end

  describe "code lens for mix.exs" do
    setup [:with_mix_exs]

    test "emits a code lens at the project definition", %{project: project, uri: referenced_uri} do
      mix_exs_path = Document.Path.ensure_path(referenced_uri)
      mix_exs = File.read!(mix_exs_path)

      {:ok, request} = build_request(mix_exs_path)
      {:reply, %{result: lenses}} = handle(request, project)

      assert [%Types.CodeLens{} = code_lens] = lenses

      assert extract(mix_exs, code_lens.range) =~ "def project"
      assert code_lens.command == Handlers.Commands.reindex_command(project)
    end
  end
end
