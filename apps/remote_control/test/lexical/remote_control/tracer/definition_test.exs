defmodule Lexical.RemoteControl.Tracer.DefinitionTest do
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.Tracer.Definition
  alias Lexical.SourceFile.Store, as: SourceFileStore
  alias Lexical.SourceFile

  import Messages
  import Lexical.Test.Fixtures

  use ExUnit.Case, async: true

  def with_real_project(%{project: project}) do
    {:ok, _, _} = RemoteControl.start_link(project, self())
    Build.schedule_compile(project, true)

    on_exit(fn ->
      :ok = RemoteControl.stop(project)
    end)

    :ok
  end

  def open_file(project, relative_path) do
    uri = file_uri(project, relative_path)
    {:ok, source_file} = SourceFileStore.open_temporary(uri)
    source_file
  end

  setup do
    {:ok, _} = start_supervised(SourceFile.Store)
    project = project(:compilation_tracers)
    {:ok, project: project}
  end

  describe "module definition" do
    setup [:with_real_project]

    test "cursor at `__MODULE__`", %{project: project} do
      file = open_file(project, "lib/compilation_tracers/module_references_by_self.ex")
      position = {2, 3}

      assert_receive project_compiled(status: :success), 200

      RemoteControl.call(project, State, :get_moudle_info_by_name, [
        CompilationTracers.ModuleReferencesBySelf1
      ])

      assert %{
               range: %Lexical.SourceFile.Range{
                 start: %Lexical.SourceFile.Position{line: 0, character: 10},
                 end: %Lexical.SourceFile.Position{line: 0, character: 52}
               },
               uri: uri
             } = Definition.definition(project, file, position)

      assert String.ends_with?(uri, "compilation_tracers/module_references_by_self.ex")
    end
  end
end
