defmodule Lexical.Server.TaskQueueTest do
  alias Lexical.Protocol.Notifications
  alias Lexical.Protocol.Requests
  alias Lexical.Server.Configuration
  alias Lexical.Server.Provider.Handlers
  alias Lexical.Server.TaskQueue
  alias Lexical.Server.Transport
  alias Lexical.Test.Fixtures

  use ExUnit.Case
  use Patch
  use Lexical.Test.EventualAssertions

  setup_all do
    {:ok, config: Configuration.new(project: Fixtures.project())}
  end

  setup do
    {:ok, _} = start_supervised({Task.Supervisor, name: TaskQueue.task_supervisor_name()})
    {:ok, _} = start_supervised(TaskQueue)
    unit_test = self()
    patch(Transport, :write, &send(unit_test, &1))

    :ok
  end

  def request(config, func) do
    id = System.unique_integer([:positive])

    patch(Lexical.Server, :handler_for, fn _ -> {:ok, Handlers.Completion} end)

    patch(Handlers.Completion, :handle, fn request, %Configuration{} = ^config ->
      func.(request, config)
    end)

    patch(Requests.Completion, :to_elixir, fn req -> {:ok, req} end)

    request = Requests.Completion.new(id: id, text_document: nil, position: nil, context: nil)

    {id, {Handlers.Completion, :handle, [request, config]}}
  end

  describe "size/0" do
    test "an empty queue has size 0" do
      assert 0 == TaskQueue.size()
    end

    test "adding a request makes the queue grow", %{config: config} do
      {id, mfa} = request(config, fn _, _ -> Process.sleep(500) end)
      assert :ok = TaskQueue.add(id, mfa)
      assert 1 == TaskQueue.size()
    end
  end

  describe "cancel/1" do
    test "canceling a request stops it", %{config: config} do
      {id, mfa} = request(config, fn _, _ -> Process.sleep(500) end)

      assert :ok = TaskQueue.add(id, mfa)
      assert :ok = TaskQueue.cancel(id)

      assert_receive %{id: ^id, error: error}

      assert TaskQueue.size() == 0
      assert error.code == :request_cancelled
      assert error.message == "Request cancelled"
    end

    test "passing in a request for cancellation", %{config: config} do
      {id, mfa} = request(config, fn _, _ -> Process.sleep(500) end)

      assert :ok = TaskQueue.add(id, mfa)
      assert :ok = TaskQueue.cancel(id)

      assert_receive %{id: ^id, error: error}
      assert TaskQueue.size() == 0
      assert error.code == :request_cancelled
      assert error.message == "Request cancelled"
    end

    test "canceling a non-existing request is a no-op" do
      assert :ok = TaskQueue.cancel("5")
      refute_receive %{id: _}
    end

    test "Adding a cancel notification cancels the request", %{config: config} do
      {id, mfa} = request(config, fn _, _ -> Process.sleep(500) end)
      assert :ok = TaskQueue.add(id, mfa)

      {:ok, notif} =
        Notifications.Cancel.parse(%{
          "method" => "$/cancelRequest",
          "jsonrpc" => "2.0",
          "params" => %{
            "id" => id
          }
        })

      assert :ok = TaskQueue.cancel(notif)
      assert_receive %{id: ^id, error: error}
      assert TaskQueue.size() == 0
      assert error.code == :request_cancelled
      assert error.message == "Request cancelled"
    end

    test "Adding a cancel request cancels the request", %{config: config} do
      {id, mfa} = request(config, fn _, _ -> Process.sleep(500) end)
      assert :ok = TaskQueue.add(id, mfa)

      {:ok, req} =
        Requests.Cancel.parse(%{
          "method" => "$/cancelRequest",
          "jsonrpc" => "2.0",
          "id" => "50",
          "params" => %{
            "id" => id
          }
        })

      assert :ok = TaskQueue.cancel(req)
      assert_receive %{id: ^id, error: error}
      assert TaskQueue.size() == 0
      assert error.code == :request_cancelled
      assert error.message == "Request cancelled"
    end

    test "canceling a request that has finished is a no-op", %{config: config} do
      me = self()
      {id, mfa} = request(config, fn _, _ -> send(me, :finished) end)

      assert :ok = TaskQueue.add(id, mfa)
      assert_receive :finished

      assert :ok = TaskQueue.cancel(id)
      assert TaskQueue.size() == 0
    end
  end

  describe "task return values" do
    test "tasks can reply", %{config: config} do
      {id, mfa} = request(config, fn _, _ -> {:reply, "great"} end)
      assert :ok = TaskQueue.add(id, mfa)

      assert_receive "great"
    end

    test "replies are optional", %{config: config} do
      {id, mfa} = request(config, fn _, _ -> :noreply end)
      assert :ok = TaskQueue.add(id, mfa)

      assert_eventually TaskQueue.size() == 0
      refute_receive _
    end

    test "exceptions are handled", %{config: config} do
      {id, mfa} = request(config, fn _, _ -> raise "Boom!" end)
      assert :ok = TaskQueue.add(id, mfa)

      assert_receive %{id: ^id, error: error}
      assert error.code == :internal_error
      assert error.message =~ "Boom!"
    end
  end
end
