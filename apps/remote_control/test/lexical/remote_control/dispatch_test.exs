defmodule Lexical.RemoteControl.DispatchTest do
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.RemoteControl.Dispatch

  import Messages
  use ExUnit.Case
  use Patch

  def with_dispatch_started(_) do
    {:ok, dispatch} = start_supervised(Dispatch)
    {:ok, dispatch: dispatch}
  end

  defmodule Forwarder do
    alias Lexical.RemoteControl.Dispatch

    def start(message_types) do
      test = self()

      pid =
        spawn_link(fn ->
          Dispatch.register_listener(self(), message_types)
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

    test "allows processes to register for a message", %{dispatch: dispatch} do
      assert :ok = Dispatch.register_listener(self(), [project_compiled()])

      project_compiled = project_compiled(status: :successful)
      send(dispatch, project_compiled)
      assert_receive ^project_compiled
    end

    test "allows processes to register for any message", %{dispatch: dispatch} do
      assert :ok = Dispatch.register_listener(self(), [:all])
      send(dispatch, project_compiled(status: :successful))
      send(dispatch, module_updated())

      assert_receive project_compiled()
      assert_receive module_updated()
    end

    test "cleans up if a process dies" do
      Dispatch.register_listener(self(), [:all])
      {:ok, forwarder_pid} = Forwarder.start([:all])

      assert Dispatch.registered?(forwarder_pid)
      :ok = Forwarder.stop(forwarder_pid)
      refute Dispatch.registered?(forwarder_pid)
    end

    test "handles multiple registrations", %{dispatch: dispatch} do
      {:ok, forwarder_1} = Forwarder.start([project_compiled()])
      {:ok, forwarder_2} = Forwarder.start([module_updated()])
      {:ok, forwarder_3} = Forwarder.start([:all])

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
