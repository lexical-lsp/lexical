defmodule Lexical.RemoteControl.TracerTest do
  alias Lexical.Project
  alias Lexical.RemoteControl.Tracer
  alias Lexical.SourceFile.Store, as: SourceFileStore

  import Lexical.Test.Fixtures
  use ExUnit.Case, async: false

  @subject Tracer

  setup_all do
    options = Code.compiler_options()
    parser_options = [columns: true, token_metadata: true]

    Code.put_compiler_option(:tracers, [@subject])
    # if just use compile_quoted, then no need this parser_options
    Code.put_compiler_option(:parser_options, parser_options)
    Code.put_compiler_option(:warnings_as_errors, false)

    start_supervised!(@subject)
    start_supervised(SourceFileStore)
    project_dir = Project.root_path(project())
    Tracer.set_project_dir(project_dir)

    on_exit(fn ->
      Code.compiler_options(options)
    end)
  end

  def traced_project() do
    project_name = to_string(:compilation_tracers)
    fixture_dir = Path.join(fixtures_path(), project_name)
    Project.new("file://#{fixture_dir}")
  end

  setup do
    %{project: traced_project()}
  end

  describe "trace module definition" do
    test "handles single module", %{project: project} do
      file = file_path(project, "lib/compilation_tracers/references_referenced.ex")
      Code.compile_file(file)
    end
  end
end

