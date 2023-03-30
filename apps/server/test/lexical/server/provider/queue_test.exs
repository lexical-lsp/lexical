defmodule Lexical.Server.Provider.QueueTest do
  alias Lexical.Protocol.Requests
  alias Lexical.Server.Provider.Env
  alias Lexical.Server.Provider.Handlers
  alias Lexical.Server.Provider.Queue
  alias Lexical.Server.Transport

  use ExUnit.Case
  use Patch
  use Testing.EventualAssertions

  setup do
    {:ok, _} = start_supervised(Queue.Supervisor.child_spec())
    {:ok, _} = start_supervised(Queue)
    unit_test = self()
    patch(Transport, :write, &send(unit_test, &1))

    :ok
  end

  def request(id, func) do
    patch(Handlers.Completion, :handle, fn request, env -> func.(request, env) end)
    patch(Handlers, :for_request, fn _ -> {:ok, Handlers.Completion} end)
    patch(Requests.Completion, :to_elixir, fn req -> {:ok, req} end)
    Requests.Completion.new(id: id, text_document: nil, position: nil, context: nil)
  end

  describe "size/0" do
    test "an empty queue has size 0" do
      assert 0 == Queue.size()
    end

    test "adding a request makes the queue grow" do
      request = request(1, fn _, _ -> Process.sleep(500) end)
      assert :ok = Queue.add(request, Env.new())
      assert 1 == Queue.size()
    end
  end

  describe "cancel/1" do
    test "canceling a request stops it" do
      request = request("1", fn _, _ -> Process.sleep(500) end)
      assert :ok = Queue.add(request, Env.new())

      :ok = Queue.cancel("1")

      assert_receive %{id: "1", error: error}

      assert Queue.size() == 0
      assert error.code == :request_cancelled
      assert error.message == "Request cancelled"
    end

    test "integers are stringified" do
      request = request("1", fn _, _ -> Process.sleep(500) end)
      assert :ok = Queue.add(request, Env.new())

      :ok = Queue.cancel(1)

      assert_receive %{id: "1", error: _}
    end

    test "passing in a request for cancellation" do
      request = request("1", fn _, _ -> Process.sleep(500) end)
      :ok = Queue.add(request, Env.new())

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
  end

  describe "task return values" do
    test "tasks can reply" do
      request = request("1", fn _, _ -> {:reply, "great"} end)
      :ok = Queue.add(request, Env.new())

      assert_receive "great"
    end

    test "replies are optional" do
      request = request("1", fn _, _ -> :noreply end)
      :ok = Queue.add(request, Env.new())

      assert_eventually Queue.size() == 0
      refute_receive _
    end

    test "the server can be notified about the request" do
      unit_test = self()
      request = request("1", fn _, _ -> {:reply_and_alert, :response} end)

      patch(Lexical.Server, :response_complete, fn request, reply ->
        send(unit_test, {:request_complete, request, reply})
      end)

      :ok = Queue.add(request, Env.new())

      assert_receive :response
      assert_receive {:request_complete, ^request, :response}
    end

    test "exceptions are handled" do
      request = request("1", fn _, _ -> raise "Boom!" end)
      assert :ok = Queue.add(request, Env.new())

      assert_receive %{id: "1", error: error}
      assert error.code == :internal_error
      assert error.message =~ "Boom!"
    end
  end
end
