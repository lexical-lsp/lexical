defmodule Lexical.Server.Project.Progress.State do
  alias Lexical.Project
  alias Lexical.Protocol.Notifications
  alias Lexical.Server.Project.Progress.Value
  alias Lexical.Server.Transport

  require Logger

  defstruct project: nil, token_by_label: %{}, progress: nil

  def new(%Project{} = project) do
    %__MODULE__{project: project}
  end

  def begin(%__MODULE__{} = state, label) do
    token = System.unique_integer([:positive])
    token_by_label = Map.put(state.token_by_label, label, token)

    state = %{state | token_by_label: token_by_label}
    create_work_done(state, label)

    progress = value(:begin, state, label, nil)
    write(progress)

    %{state | progress: progress}
  end

  def update(%__MODULE__{} = state, label, message) do
    progress = value(:report, state, label, message)
    write(progress)
    %{state | progress: progress}
  end

  def complete(%__MODULE__{} = state, label, message) do
    progress = value(:end, state, label, message)
    write(progress)
    state = clear_token_by_label(state, label)
    %{state | progress: progress}
  end

  defp create_work_done(%__MODULE__{} = state, label) do
    token = get_token(state, label)
    progress = Notifications.CreateWorkDoneProgress.new(token: token)
    Transport.write(progress)
  end

  defp write(%{token: token} = progress) when not is_nil(token) do
    progress |> Value.to_progress() |> Transport.write()
  end

  defp write(_), do: :ok

  defp value(:begin, state, label, _message) do
    token = get_token(state, label)
    Value.new(kind: :begin, token: token, title: label)
  end

  defp value(:report, state, label, message) do
    token = get_token_when_update(state, label)
    Value.new(kind: :report, token: token, message: message)
  end

  defp value(:end, state, label, message) do
    token = get_token(state, label)
    Value.new(kind: :end, token: token, message: message)
  end

  defp clear_token_by_label(%__MODULE__{} = state, label) do
    token_by_label = Map.delete(state.token_by_label, label)
    %{state | token_by_label: token_by_label}
  end

  defp get_token_when_update(state, label) do
    case label do
      "mix compile" ->
        # NOTE: `mix compile` updating event is from the compile tracer
        # Then this tracer can be triggered by both `mix deps.compile` and `mix compile`.
        get_token(state, "mix compile") || get_token(state, "mix deps.compile")

      _ ->
        get_token(state, label)
    end
  end

  defp get_token(state, label) do
    state.token_by_label[label]
  end
end
