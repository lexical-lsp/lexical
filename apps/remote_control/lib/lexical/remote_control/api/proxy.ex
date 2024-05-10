defmodule Lexical.RemoteControl.Api.Proxy do
  @moduledoc """
  A bimodal buffering proxy

  This proxy has two modes. In its default mode, it simply forwards function calls to another module, but when
  buffering is activated, it will buffer requests and returned canned responses.
  When a process calls `start_buffering`, it is monitored, and while it's alive, all messages are buffered. When the
  process that calls `start_buffering` exits, the messages that are buffered then have the potential to be emitted.

   Buffered request are subject to the proxy's internal logic. Some requests that are time sensitive
  (like formatting) are dropped. Others are deduplicated, while others are reordered.

  The logic follows below
    `broadcast` - Buffered - Though, those related to other events, like compilation are subject to
                  the rules that govern their source events.
    `schedule_compile` - Buffered - Only one call is kept
    `compile_document` - Buffered, though only one call per URI is kept, and if a `schedule_compile` call
                         was buffered, all `compile_document` calls are dropped
    `reindex`  - Buffered, though only one call is kept and it is the last thing run.
    `index_running?` - Dropped because it requires an immediate response
    `format`  - Dropped, as it requires an immediate response. Responds immediately with empty changes

  """
  alias Lexical.Document
  alias Lexical.Document.Changes
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.RemoteControl.Api.Proxy.Records
  alias Lexical.RemoteControl.Api.Proxy.State
  alias Lexical.RemoteControl.CodeMod
  alias Lexical.RemoteControl.Commands

  import Messages
  import Record
  import Records, only: :macros

  @behaviour :gen_statem

  defrecord :buffer, contents: nil, return: :ok
  defrecord :drop, contents: nil, return: :ok

  # public API

  def start_buffering do
    start_buffering(self())
  end

  def start_buffering(caller) when is_pid(caller) do
    :gen_statem.call(__MODULE__, {:start_buffering, caller})
  end

  # proxied functions

  def broadcast(percent_progress() = message) do
    RemoteControl.Dispatch.broadcast(message)
  end

  def broadcast(message) do
    message = message(body: message)
    :gen_statem.call(__MODULE__, buffer(contents: message))
  end

  def schedule_compile(force? \\ false) do
    project = RemoteControl.get_project()

    mfa = to_mfa(RemoteControl.Build.schedule_compile(project, force?))
    :gen_statem.call(__MODULE__, buffer(contents: mfa))
  end

  def compile_document(document) do
    project = RemoteControl.get_project()

    mfa = to_mfa(RemoteControl.Build.compile_document(project, document))

    :gen_statem.call(__MODULE__, buffer(contents: mfa))
  end

  def reindex do
    mfa = to_mfa(Commands.Reindex.perform())
    :gen_statem.call(__MODULE__, buffer(contents: mfa))
  end

  def index_running? do
    mfa = to_mfa(Commands.Reindex.running?())
    :gen_statem.call(__MODULE__, drop(contents: mfa, return: false))
  end

  def format(%Document{} = document) do
    mfa = to_mfa(CodeMod.Format.edits(document))
    drop = drop(contents: mfa, return: {:ok, Changes.new(document, [])})
    :gen_statem.call(__MODULE__, drop)
  end

  # utility functions

  def buffering? do
    :gen_statem.call(__MODULE__, :buffering?)
  end

  # :gen_statem callbacks
  def start_link do
    :gen_statem.start_link({:local, __MODULE__}, __MODULE__, [], [])
  end

  @impl :gen_statem
  def init(_) do
    {:ok, :proxying, nil}
  end

  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []}
    }
  end

  @impl :gen_statem
  def callback_mode, do: :state_functions

  # callbacks for proxying mode

  def proxying({:call, from}, {:start_buffering, caller}, _state) do
    Process.monitor(caller)
    {:next_state, :buffering, State.new(caller), [{:reply, from, :ok}]}
  end

  def proxying({:call, from}, buffer(contents: contents), state) do
    {:keep_state, state, [{:reply, from, apply(contents)}]}
  end

  def proxying({:call, from}, drop(contents: contents), state) do
    {:keep_state, state, [{:reply, from, apply(contents)}]}
  end

  def proxying({:call, from}, :buffering?, state) do
    {:keep_state, state, [{:reply, from, false}]}
  end

  # Callbacks for buffering mode

  def buffering({:call, from}, {:start_buffering, _}, %State{} = state) do
    {:keep_state, state, [{:reply, from, {:error, {:already_buffering, state.initiator_pid}}}]}
  end

  def buffering({:call, from}, buffer(contents: mfa() = mfa, return: return), %State{} = state) do
    state = State.add_mfa(state, mfa)
    {:keep_state, state, [{:reply, from, return}]}
  end

  def buffering({:call, from}, buffer(contents: message() = message), %State{} = state) do
    state = State.add_message(state, message)
    {:keep_state, state, [{:reply, from, :ok}]}
  end

  def buffering({:call, from}, drop(return: return), %State{} = state) do
    {:keep_state, state, [{:reply, from, return}]}
  end

  def buffering(:info, {:DOWN, _, :process, pid, _}, %State{initiator_pid: pid} = state) do
    state
    |> State.flush()
    |> Enum.each(&apply/1)

    {:next_state, :proxying, nil}
  end

  def buffering({:call, from}, :buffering?, state) do
    {:keep_state, state, [{:reply, from, true}]}
  end

  # Private

  defp apply(mfa(module: module, function: function, arguments: arguments)) do
    apply(module, function, arguments)
  end

  defp apply(message(body: message)) do
    RemoteControl.Dispatch.broadcast(message)
  end
end
