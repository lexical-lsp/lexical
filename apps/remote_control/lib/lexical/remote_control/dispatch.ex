defmodule Lexical.RemoteControl.Dispatch do
  @moduledoc """
  A global event dispatcher for lexical.

  Dispatch allows two recipients of its messages, processes and modules. A process must register
  itself via a call to `register_listener`, while a process must implement the
  `Lexical.RemoteControl.Dispatch.Handler` behaviour and add the module to the @handlers module attribute.
  """
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Dispatch.PubSub
  import Lexical.RemoteControl.Api.Messages

  @handlers [PubSub]

  # public API

  @doc """
  Registers a process that will receive messages sent directly to its pid.
  """

  def register_listener(listener_pid, message_types) when is_list(message_types) do
    :gen_event.call(__MODULE__, PubSub, PubSub.register_message(listener_pid, message_types))
  end

  def register_listener(listener_pid, event_or_all) do
    register_listener(listener_pid, List.wrap(event_or_all))
  end

  def add_handler(handler_module, init_args \\ []) do
    :gen_event.add_handler(__MODULE__, handler_module, init_args)
  end

  def registered?(pid) when is_pid(pid) do
    :gen_event.call(__MODULE__, PubSub, PubSub.registered_message(pid))
  end

  def registered?(name) when is_atom(name) do
    name in :gen_event.which_handlers(__MODULE__)
  end

  def broadcast(message) do
    :gen_event.notify(__MODULE__, message)
  end

  # GenServer callbacks

  def start_link(_) do
    case :gen_event.start_link(name()) do
      {:ok, pid} = success ->
        Enum.each(@handlers, &:gen_event.add_handler(pid, &1, []))
        register_progress_listener()
        success

      error ->
        error
    end
  end

  def child_spec(_) do
    %{
      id: {__MODULE__, :dispatch},
      start: {__MODULE__, :start_link, [[]]}
    }
  end

  defp name do
    {:local, __MODULE__}
  end

  defp register_progress_listener do
    register_listener(progress_pid(), [project_progress()])
  end

  def progress_pid do
    project = RemoteControl.get_project()
    master_node_name = RemoteControl.master_node_name(project)
    progress_name = :rpc.call(master_node_name, Lexical.Server.Project.Progress, :name, [project])
    :rpc.call(master_node_name, Process, :whereis, [progress_name])
  end
end
