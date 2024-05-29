defmodule Lexical.RemoteControl.Api.Proxy.ProxyingState do
  alias Lexical.RemoteControl.Api.Proxy.Records

  defstruct refs_to_from: %{}

  import Records

  def new do
    %__MODULE__{}
  end

  def apply_mfa(
        %__MODULE__{} = state,
        from,
        mfa(module: module, function: function, arguments: arguments)
      ) do
    task = Task.async(module, function, arguments)

    %__MODULE__{
      state
      | refs_to_from: Map.put(state.refs_to_from, task.ref, from)
    }
  end

  def reply(%__MODULE__{} = state, ref, reply) do
    {from, new_refs_to_from} = Map.pop(state.refs_to_from, ref)
    :gen_statem.reply(from, reply)
    %__MODULE__{state | refs_to_from: new_refs_to_from}
  end

  def empty?(%__MODULE__{} = state) do
    Enum.empty?(state.refs_to_from)
  end
end
