defmodule Lexical.RemoteControl.Search.Store.Backends.Mnesia.State do
  alias Lexical.Project
  alias Lexical.RemoteControl.Search.Store.Backends.Mnesia.State.Connection

  defdelegate connect_to_node(state), to: Connection
  defdelegate ensure_node_exists(state), to: Connection
  defdelegate on_nodedown(state, node_name), to: Connection
  defdelegate on_port_closed(state, port_ref), to: Connection

  defstruct [:project, :port, :port_ref, :mnesia_node, :leader?, :leader_pid]

  def new(%Project{} = project) do
    %__MODULE__{project: project}
  end

  def rpc_call(%__MODULE__{} = state, m, f, a) do
    :rpc.call(state.mnesia_node, m, f, a)
  end
end
