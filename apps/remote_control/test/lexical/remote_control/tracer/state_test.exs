defmodule Lexical.RemoteControl.Tracer.StateTest do
  alias Lexical.RemoteControl.Tracer.State
  alias Lexical.Project
  alias Lexical.RemoteControl.Tracer

  import Lexical.Test.Fixtures
  use ExUnit.Case, async: false

  @subject Tracer

  def traced_project() do
    project_name = to_string(:compilation_tracers)
    fixture_dir = Path.join(fixtures_path(), project_name)
    Project.new("file://#{fixture_dir}")
  end

  setup_all do
    options = Code.compiler_options()
    parser_options = [columns: true, token_metadata: true]

    Code.put_compiler_option(:tracers, [@subject])
    # if just use compile_quoted, then no need this parser_options
    Code.put_compiler_option(:parser_options, parser_options)
    Code.put_compiler_option(:warnings_as_errors, false)

    start_supervised!(@subject)
    project_dir = Project.root_path(traced_project())
    File.mkdir_p!(Path.join(project_dir, ".lexical"))
    Tracer.set_project_dir(project_dir)

    on_exit(fn ->
      Code.compiler_options(options)
      File.rm_rf(Path.join(project_dir, ".lexical"))
    end)
  end

  setup do
    %{project: traced_project()}
  end

  describe "get_module_range_by_file_and_line/2" do
    test "handles single module", %{project: project} do
      file = file_path(project, "lib/compilation_tracers/references_referenced.ex")
      Code.compile_file(file)

      assert State.get_module_range_by_file_and_line(file, 2) ==
               %{end: %{character: 50, line: 1}, start: %{character: 11, line: 1}}
    end

    test "handles multiple modules", %{project: project} do
      file = file_path(project, "lib/compilation_tracers/module_references_by_self.ex")
      Code.compile_file(file)

      assert State.get_module_range_by_file_and_line(file, 2) ==
               %{end: %{character: 53, line: 1}, start: %{character: 11, line: 1}}

      assert State.get_module_range_by_file_and_line(file, 6) ==
               %{end: %{character: 53, line: 5}, start: %{character: 11, line: 5}}

      assert State.get_module_range_by_file_and_line(file, 11) ==
               %{end: %{character: 23, line: 10}, start: %{character: 13, line: 10}}
    end
  end

  describe "get_alias_mapping_by_file_and_line/2" do
    setup %{project: project} do
      references_file = file_path(project, "lib/compilation_tracers/references_referenced.ex")
      Code.compile_file(references_file)
    end

    test "no alias mapping at the first alias line", %{project: project} do
      file = file_path(project, "lib/compilation_tracers/references_alias.ex")
      Code.compile_file(file)
      assert State.get_alias_mapping_by_file_and_line(file, 2) == %{}
    end

    test "show all alias mappint at the referenced line", %{project: project} do
      file = file_path(project, "lib/compilation_tracers/references_alias.ex")
      Code.compile_file(file)

      assert State.get_alias_mapping_by_file_and_line(file, 8) == %{
               "Elixir.Other": CompilationTracers.ReferencesReferenced,
               "Elixir.ReferencesReferenced": CompilationTracers.ReferencesReferenced,
               "Elixir.Some": CompilationTracers.ReferencesReferenced
             }
    end
  end

  describe "get_call_by_file_and_position/2" do
    test "handles local function call", %{project: project} do
      file = file_path(project, "lib/compilation_tracers/references_referenced.ex")
      Code.compile_file(file)

      assert %{
               callee: {CompilationTracers.ReferencesReferenced, :referenced_fun, 0},
               column: 5,
               line: 22
             } = State.get_call_by_file_and_position(file, {22, 5})
    end

    test "handles remote function call", %{project: project} do
      references_file = file_path(project, "lib/compilation_tracers/references_referenced.ex")
      file = file_path(project, "lib/compilation_tracers/references_remote.ex")
      Code.compile_file(references_file)
      Code.compile_file(file)

      assert %{
               callee: {CompilationTracers.ReferencesReferenced, :referenced_fun, 0},
               column: 26,
               line: 5
             } = State.get_call_by_file_and_position(file, {5, 26})
    end

    test "handles remote function call when using use to import", %{project: project} do
      references_file = file_path(project, "lib/compilation_tracers/references_referenced.ex")
      file = file_path(project, "lib/compilation_tracers/references_imported_by_use.ex")
      Code.compile_file(references_file)
      Code.compile_file(file)

      assert %{
               callee: {CompilationTracers.ReferencesReferenced, :referenced_fun, 0},
               column: 5,
               line: 5
             } = State.get_call_by_file_and_position(file, {5, 5})
    end
  end

  describe "get_def_info_by_mfa/1" do
    test "returns function def info by mfa", %{project: project} do
      file = file_path(project, "lib/compilation_tracers/references_referenced.ex")
      Code.compile_file(file)

      assert %{
               range: %{end: %{character: 21, line: 8}, start: %{character: 7, line: 8}}
             } =
               State.get_def_info_by_mfa(
                 {CompilationTracers.ReferencesReferenced, :referenced_fun, 0}
               )
    end
  end
end
