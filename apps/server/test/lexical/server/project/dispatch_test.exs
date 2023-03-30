defmodule Lexical.Server.Project.DispatchTest do
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.Server.Project.Dispatch

  import Messages
  import Lexical.Test.Fixtures
  use ExUnit.Case
  use Patch

  setup do
    {:ok, project: project()}
  end

  def with_dispatch_started(%{project: project}) do
    patch(RemoteControl, :start_link, {:ok, :node})
    patch(RemoteControl.Api, :schedule_compile, :ok)
    patch(RemoteControl.Api, :list_modules, [])
    {:ok, dispatch} = start_supervised({Dispatch, project})

    {:ok, dispatch: dispatch}
  end

  defmodule Forwarder do
    alias Lexical.Server.Project.Dispatch

    def start(%Project{} = project, message_types) do
      test = self()

      pid =
        spawn_link(fn ->
          Dispatch.register(project, message_types)
          send(test, :ready)

          loop(test)
        end)

      receive do
        :ready ->
          {:ok, pid}
      end
    end

    def stop(pid) do
      ref = Process.monitor(pid)
      Process.unlink(pid)
      Process.exit(pid, :kill)

      receive do
        {:DOWN, ^ref, _, _, _} -> :ok
      end
    end

    def loop(parent) do
      receive do
        msg -> send(parent, {:forwarded, self(), msg})
      end

      loop(parent)
    end
  end

  describe "a running project" do
    setup [:with_dispatch_started]

    test "allows processes to register for a message", %{project: project, dispatch: dispatch} do
      assert :ok = Dispatch.register(project, [project_compiled()])

      project_compiled = project_compiled(status: :successful)
      send(dispatch, project_compiled)
      assert_receive ^project_compiled
    end

    test "allows processes to register for any message", %{project: project, dispatch: dispatch} do
      assert :ok = Dispatch.register(project, [:all])
      send(dispatch, project_compiled(status: :successful))
      send(dispatch, module_updated())

      assert_receive project_compiled()
      assert_receive module_updated()
    end

    test "cleans up if a process dies", %{project: project} do
      Dispatch.register(project, [:all])
      {:ok, forwarder_pid} = Forwarder.start(project, [:all])

      assert Dispatch.registered?(project, forwarder_pid)
      :ok = Forwarder.stop(forwarder_pid)
      refute Dispatch.registered?(project, forwarder_pid)
    end

    test "handles multiple registrations", %{project: project, dispatch: dispatch} do
      {:ok, forwarder_1} = Forwarder.start(project, [project_compiled()])
      {:ok, forwarder_2} = Forwarder.start(project, [module_updated()])
      {:ok, forwarder_3} = Forwarder.start(project, [:all])

      send(dispatch, module_updated())
      send(dispatch, project_compiled())
      send(dispatch, {:other, :message})

      assert_receive {:forwarded, ^forwarder_1, project_compiled()}
      assert_receive {:forwarded, ^forwarder_2, module_updated()}

      assert_receive {:forwarded, ^forwarder_3, project_compiled()}
      assert_receive {:forwarded, ^forwarder_3, module_updated()}
      assert_receive {:forwarded, ^forwarder_3, {:other, :message}}
    end
  end
end
