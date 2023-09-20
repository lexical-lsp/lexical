defmodule Lexical.RemoteControl.Search.Store.Backends.Mnesia.State.Connection do
  @moduledoc """
  Connection handling for mnesia.

  Mnesia has the most persnickety setup I've ever seen. This doc is so someone reading this in a year can understand what's
  going on here.

  Mnesia has some restrictions that makes things complicated for lexical. First off, it needs to run on a node with
  a stable name. Lexical, however, generates random-ish node names to prevent collisions. This presents a problem:
  How do we start mnesia? The path I chose was to launch another node with a stable name (mnesia-<project.name>) and
  have that "own" mnesia. It doesn't need to do anything other than be the primary mnesia node.

  Even with that decision, starting mnesia is tricky because there are a couple cases:

    1. It's being started on a new database
    2. It's being started with an existing database
    3. Someone is using more than one editor on the same project, and the new node needs to share access to mnesia and
       join the cluster.

  To that end, this module exports a couple of functions and makes heavy use of `:global` to select a leader.
  The first step is to call `connect(/1)`, which checks if a leader is registered globally, and if not, then the
  current pid is registered as the leader, and the port is started. Once that happens, connect returns
  `{:connect_to_node, new_state}`, and the new state reflects if the state is the leader or not.

  Then, we need ensure we're connected to the mnesia node. This is done via `connect_to_node/1`, which uses
  `:erl_epmd` to see if the mnesia node is up, and if so, attempts a connection to it. If any of these steps fail,
  `{:connect_to_node, state}` is returned, and the process begins anew.

  If a connection is achieved, The leader is let through first (by dint of it being nearly impossible to get a race
  by running multiple editors by hand. This isn't _really_ a distributed system), at which point, it initializes mnesia.
  inside of a lock. When this lock is released, followers will get through the lock and join mnesia as ram copies

  ## Mnesia initialization process

  When mnesia starts, it goes through the following process:

    1. Possibly creates a schema. We return `:ok` if a schema is newly created, or if it already exists. All other
       errors are returned
    2. Call `:mnesia.start()` on the mnesia controller node.
    3. Create the table on the remote node. Similar to creating the schema, `:ok` is returned if it is newly created,
       or if it already exists.
    4. Have the local node join the mnesia cluster as a ram copy
    5. Clean old ram copies from the cluster

  The last is worth explaining. Since lexical generates node names, and schemas are static, starting and stopping
  the language server will result in mnesia accumulating a bunch of ram copy nodes that aren't actually in the cluster.
  I don't know if this is bad, but it seems like this should be cleaned up.

  Stuff I don't know yet:

  1. Do we need the local nodes to have ram copies? Things would be a lot simpler if we didn't, but I was a little
     worried about the ergonomics and performance of using :rpc for all queries. The tradeoff, of course is that data
     is duplicated on every node. This might be a memory issue on large projects
  """
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Search.Store.Backends.Mnesia.Schema
  alias Lexical.RemoteControl.Search.Store.Backends.Mnesia.State

  @leader_name :mnesia_leader

  def ensure_node_exists(%State{} = state) do
    case :global.register_name(@leader_name, self()) do
      :yes ->
        start_port(state)

      :no ->
        leader_pid = :global.whereis_name(@leader_name)
        Process.monitor(leader_pid)
        %State{state | leader?: false, leader_pid: leader_pid}
    end
  end

  def connect_to_node(%State{} = state) do
    with true <- mnesia_running?(state.project),
         true <- connect_to_mnesia(state.project) do
      new_state = %State{state | mnesia_node: mnesia_node_name(state.project)}
      initialize_mnesia(new_state)
    else
      _ ->
        {:connect_to_node, state}
    end
  end

  def on_nodedown(%State{leader?: true, mnesia_node: mnesia_node} = state, mnesia_node) do
    {:ok, port, ref} = initialize_mnesia_node(state.project)
    {:connect_to_node, %State{state | port: port, port_ref: ref}}
  end

  def on_nodedown(%State{} = state, _) do
    {:connect_to_node, state}
  end

  def on_port_closed(%State{leader?: true, port_ref: port_ref} = state, port_ref) do
    {:ok, port, ref} = initialize_mnesia_node(state.project)
    new_state = %State{state | port: port, port_ref: ref}
    {:connect_to_node, new_state}
  end

  def on_port_closed(%State{} = state, _) do
    {:connect_to_node, state}
  end

  defp start_port(%State{} = state) do
    caller = self()

    with_leader_lock(:start_port, fn ->
      with :ok <- ensure_leader(caller),
           {:ok, port, ref} <- initialize_mnesia_node(state.project) do
        %State{state | port: port, port_ref: ref, leader?: true}
      end
    end)
  end

  defp initialize_mnesia(%State{leader?: true} = state) do
    # Note: It would be great to guarantee that the leader comes through here first.
    # I don't know if this will do it or not.
    with_leader_lock(:initialize, fn ->
      with :ok <- Schema.ensure_schema(state),
           :ok <- start_remote_mnesia(state),
           :ok <- Schema.create_table(state) do
        join_mnesia_as_ram_copy(state)
        Schema.clean_old_ram_copies(state)
        Schema.wait_for_tables()
        {:connected, state}
      end
    end)
  end

  defp initialize_mnesia(%State{} = state) do
    with_leader_lock(:initialize, fn ->
      :ok = join_mnesia_as_ram_copy(state)
      Schema.wait_for_tables()
      {:connected, state}
    end)
  end

  defp initialize_mnesia_node(%Project{} = project) do
    path_args = Enum.flat_map(:code.get_path(), fn path -> ["-pa", "\"#{path}\""] end)

    this_node = inspect(Node.self())

    port_args = [
      "--name",
      mnesia_node_name(project),
      "--cookie",
      Node.get_cookie(),
      "-e",
      ~s[Node.connect(#{this_node})],
      "--no-halt"
      | path_args
    ]

    port = RemoteControl.Port.open_elixir(project, args: port_args)

    ref = Port.monitor(port)
    {:ok, port, ref}
  end

  defp mnesia_node_name(project) do
    :"mnesia-#{Project.name(project)}@127.0.0.1"
  end

  defp mnesia_running?(%Project{} = project) do
    case :erl_epmd.names() do
      {:ok, nodes} ->
        [mnesia_node_name, _host] =
          project
          |> mnesia_node_name()
          |> Atom.to_string()
          |> String.split("@")

        mnesia_node_name = String.to_charlist(mnesia_node_name)

        Enum.any?(nodes, &match?({^mnesia_node_name, _}, &1))

      _ ->
        false
    end
  end

  defp connect_to_mnesia(%Project{} = project) do
    Node.connect(mnesia_node_name(project))
  end

  defp start_remote_mnesia(state) do
    State.rpc_call(state, :mnesia, :start, [])
  end

  defp join_mnesia_as_ram_copy(%State{} = state) do
    with :ok <- :mnesia.start() do
      Schema.create_local_schema(state)
    end
  end

  defp with_leader_lock(key, fun) do
    :global.trans({@leader_name, key}, fun)
  end

  defp ensure_leader(caller) when is_pid(caller) do
    case :global.whereis_name(@leader_name) do
      ^caller -> :ok
      _ -> {:error, {:not_leader, caller}}
    end
  end
end
