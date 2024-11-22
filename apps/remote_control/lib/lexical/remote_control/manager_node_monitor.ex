defmodule Lexical.RemoteControl.ManagerNodeMonitor do
  @moduledoc """
  A node monitor that monitors the manager node for this project, and shuts down
  the system if that node dies.
  """
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_) do
    case fetch_manager_node() do
      {:ok, manager_node} ->
        Node.monitor(manager_node, true)
        {:ok, manager_node}

      :error ->
        Logger.warning("Could not determine manager node for monitoring.")
        :ignore
    end
  end

  @impl true
  def handle_info({:nodedown, _}, state) do
    spawn(fn -> System.stop() end)
    {:noreply, state}
  end

  defp fetch_manager_node do
    Enum.find_value(Node.list(), :error, fn node_name ->
      string_name = Atom.to_string(node_name)

      if String.starts_with?(string_name, "manager-") do
        {:ok, node_name}
      else
        false
      end
    end)
  end
end
