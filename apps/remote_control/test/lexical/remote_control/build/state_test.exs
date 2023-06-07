defmodule Lexical.RemoteControl.Build.StateTest do
  alias Lexical.Document
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.Build.State

  import Lexical.Test.EventualAssertions
  import Lexical.Test.Fixtures

  use ExUnit.Case, async: false
  use Patch

  setup do
    {:ok, _} = start_supervised(Build.CaptureServer)
    {:ok, _} = start_supervised(RemoteControl.ModuleMappings)
    {:ok, _} = start_supervised(Lexical.Plugin.Coordinator)
    :ok
  end

  def document(%State{} = state, filename \\ "file.ex", source_code) do
    sequence = System.unique_integer([:monotonic, :positive])

    uri =
      state.project
      |> Project.root_path()
      |> Path.join(to_string(sequence))
      |> Path.join(filename)
      |> Document.Path.to_uri()

    Document.new(uri, source_code, 0)
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

  def with_a_valid_document(%{state: state}) do
    source = ~S[
      defmodule Testing.ValidSource do
        def add(a, b) do
          a + b
        end
      end
    ]

    document = document(state, source)
    {:ok, document: document}
  end

  describe "throttled compilation" do
    setup [:with_metadata_project, :with_a_valid_document]

    test "it doesn't compile immediately", %{state: state, document: document} do
      new_state =
        state
        |> State.on_file_compile(document)
        |> State.on_tick()

      assert State.compile_scheduled?(new_state, document.uri)
    end

    test "it compiles after a timeout", %{state: state, document: document} do
      state = State.on_file_compile(state, document)

      refute_eventually State.compile_scheduled?(State.on_tick(state), document.uri), 500
    end
  end
end
