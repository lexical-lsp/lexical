defmodule Lexical.RemoteControl.Build.StateTest do
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.Build.State
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.SourceFile
  alias Mix.Task.Compiler.Diagnostic

  import Messages
  import Lexical.Test.Fixtures

  import Testing.EventualAssertions
  use ExUnit.Case, async: false
  use Patch

  setup do
    {:ok, _} = start_supervised(Build.CaptureServer)
    :ok
  end

  def source_file(%State{} = state, filename \\ "file.ex", source_code) do
    sequence = System.unique_integer([:monotonic, :positive])

    uri =
      state.project
      |> Project.root_path()
      |> Path.join(to_string(sequence))
      |> Path.join(filename)
      |> SourceFile.Path.to_uri()

    SourceFile.new(uri, source_code, 0)
  end

  def with_project_state(project_name) do
    test = self()

    patch(RemoteControl, :notify_listener, fn msg ->
      send(test, msg)
    end)

    project_name = to_string(project_name)
    fixture_dir = Path.join(fixtures_path(), project_name)
    project = Project.new("file://#{fixture_dir}")
    state = State.new(project)

    RemoteControl.set_project(project)
    {:ok, state}
  end

  def with_metadata_project(_) do
    {:ok, state} = with_project_state(:project_metadata)
    {:ok, state: state}
  end

  def with_a_valid_source_file(%{state: state}) do
    source = ~S[
      defmodule Testing.ValidSource do
        def add(a, b) do
          a + b
        end
      end
    ]

    source_file = source_file(state, source)
    {:ok, source_file: source_file}
  end

  describe "throttled compilation" do
    setup [:with_metadata_project, :with_a_valid_source_file]

    test "it doesn't compile immediately", %{state: state, source_file: source_file} do
      new_state =
        state
        |> State.on_file_compile(source_file)
        |> State.on_tick()

      assert State.compile_scheduled?(new_state, source_file.uri)
    end

    test "it compiles after a timeout", %{state: state, source_file: source_file} do
      state = State.on_file_compile(state, source_file)

      refute_eventually State.compile_scheduled?(State.on_tick(state), source_file.uri), 500
    end
  end
end
