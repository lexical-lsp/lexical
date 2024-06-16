defmodule Lexical.Server.Provider.QueueTest do
  alias Lexical.Protocol.Notifications
  alias Lexical.Protocol.Requests
  alias Lexical.Server.Configuration
  alias Lexical.Server.Provider.Handlers
  alias Lexical.Server.Provider.Queue
  alias Lexical.Server.Transport
  alias Lexical.Test.Fixtures

  use ExUnit.Case
  use Patch
  use Lexical.Test.EventualAssertions

  setup_all do
    {:ok, config: Configuration.new(project: Fixtures.project())}
  end

  setup do
    {:ok, _} = start_supervised(Queue.Supervisor.child_spec())
    {:ok, _} = start_supervised(Queue)
    unit_test = self()
    patch(Transport, :write, &send(unit_test, &1))

    :ok
  end

  def request(id, func) do
    patch(Handlers.Completion, :handle, fn request, config -> func.(request, config) end)
    patch(Handlers, :for_request, fn _ -> {:ok, Handlers.Completion} end)
    patch(Requests.Completion, :to_elixir, fn req -> {:ok, req} end)
    Requests.Completion.new(id: id, text_document: nil, position: nil, context: nil)
  end

  describe "size/0" do
    test "an empty queue has size 0" do
      assert 0 == Queue.size()
    end

    test "adding a request makes the queue grow", %{config: config} do
      request = request(1, fn _, _ -> Process.sleep(500) end)
      assert :ok = Queue.add(request, config)
      assert 1 == Queue.size()
    end
  end

  describe "cancel/1" do
    test "canceling a request stops it", %{config: config} do
      request = request("1", fn _, _ -> Process.sleep(500) end)
      assert :ok = Queue.add(request, config)

      :ok = Queue.cancel("1")

      assert_receive %{id: "1", error: error}

      assert Queue.size() == 0
      assert error.code == :request_cancelled
      assert error.message == "Request cancelled"
    end

    test "integers are stringified", %{config: config} do
      request = request("1", fn _, _ -> Process.sleep(500) end)
      assert :ok = Queue.add(request, config)

      :ok = Queue.cancel(1)

      assert_receive %{id: "1", error: _}
    end

    test "passing in a request for cancellation", %{config: config} do
      request = request("1", fn _, _ -> Process.sleep(500) end)
      :ok = Queue.add(request, config)

      :ok = Queue.cancel(request)

      assert_receive %{id: "1", error: error}
      assert Queue.size() == 0
      assert error.code == :request_cancelled
      assert error.message == "Request cancelled"
    end

    test "canceling a non-existing request is a no-op" do
      assert :ok = Queue.cancel("5")
      refute_receive %{id: _}
    end

    test "Adding a cancel notification cancels the request", %{config: config} do
      request = request("1", fn _, _ -> Process.sleep(500) end)
      :ok = Queue.add(request, config)

      {:ok, notif} =
        Notifications.Cancel.parse(%{
          "method" => "$/cancelRequest",
          "jsonrpc" => "2.0",
          "params" => %{
            "id" => "1"
          }
        })

      :ok = Queue.cancel(notif)
      assert_receive %{id: "1", error: error}
      assert Queue.size() == 0
      assert error.code == :request_cancelled
      assert error.message == "Request cancelled"
    end

    test "Adding a cancel request cancels the request", %{config: config} do
      request = request("1", fn _, _ -> Process.sleep(500) end)
      :ok = Queue.add(request, config)

      {:ok, req} =
        Requests.Cancel.parse(%{
          "method" => "$/cancelRequest",
          "jsonrpc" => "2.0",
          "id" => "50",
          "params" => %{
            "id" => "1"
          }
        })

      :ok = Queue.cancel(req)
      assert_receive %{id: "1", error: error}
      assert Queue.size() == 0
      assert error.code == :request_cancelled
      assert error.message == "Request cancelled"
    end

    test "canceling a request that has finished is a no-op", %{config: config} do
      me = self()
      request = request("1", fn _, _ -> send(me, :finished) end)

      assert :ok = Queue.add(request, config)
      assert_receive :finished

      :ok = Queue.cancel("1")
      assert Queue.size() == 0
    end
  end

  describe "task return values" do
    test "tasks can reply", %{config: config} do
      request = request("1", fn _, _ -> {:reply, "great"} end)
      :ok = Queue.add(request, config)

      assert_receive "great"
    end

    test "replies are optional", %{config: config} do
      request = request("1", fn _, _ -> :noreply end)
      :ok = Queue.add(request, config)

      assert_eventually Queue.size() == 0
      refute_receive _
    end

    test "exceptions are handled", %{config: config} do
      request = request("1", fn _, _ -> raise "Boom!" end)
      assert :ok = Queue.add(request, config)

      assert_receive %{id: "1", error: error}
      assert error.code == :internal_error
      assert error.message =~ "Boom!"
    end
  end
end
