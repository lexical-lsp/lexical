defmodule Lexical.RemoteControl.Api.Proxy.DrainingState do
  alias Lexical.RemoteControl.Api.Proxy.BufferingState
  alias Lexical.RemoteControl.Api.Proxy.ProxyingState
  alias Lexical.RemoteControl.Api.Proxy.Records

  import Records

  defstruct [:proxying_state, :buffering_state]

  def new(%BufferingState{} = buffering_state, %ProxyingState{} = proxying_state) do
    %__MODULE__{buffering_state: buffering_state, proxying_state: proxying_state}
  end

  def drained?(%__MODULE__{} = state) do
    ProxyingState.empty?(state.proxying_state)
  end

  def reply(%__MODULE__{} = state, ref, reply) do
    new_state = ProxyingState.reply(state.proxying_state, ref, reply)
    %__MODULE__{state | proxying_state: new_state}
  end

  def add_mfa(%__MODULE__{} = state, mfa() = mfa) do
    new_buffering_state = BufferingState.add_mfa(state.buffering_state, mfa)
    %__MODULE__{state | buffering_state: new_buffering_state}
  end
end
