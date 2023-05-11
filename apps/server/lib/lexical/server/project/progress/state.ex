defmodule Lexical.Server.Project.Progress.State do
  alias Lexical.Project
  alias Lexical.Protocol.Notifications
  alias Lexical.Server.Project.Progress.Value
  alias Lexical.Server.Transport

  import Lexical.RemoteControl.Api.Messages

  defstruct project: nil, token_by_label: %{}, progress: nil

  def new(%Project{} = project) do
    %__MODULE__{project: project}
  end

  def begin(%__MODULE__{} = state, project_progress(label: label)) do
    token = System.unique_integer([:positive])
    token_by_label = Map.put(state.token_by_label, label, token)

    state = %{state | token_by_label: token_by_label}
    write_work_done(state, label)

    progress = Value.new(token, :begin, label)
    write(progress)

    %{state | progress: progress}
  end

  def report(%__MODULE__{} = state, project_progress(label: label, message: message)) do
    token = get_token_when_update(state, label)

    progress = Value.new(token, :report, message)
    write(progress)

    %{state | progress: progress}
  end

  def complete(%__MODULE__{} = state, project_progress(label: label, message: message)) do
    token = get_token(state, label)

    progress = Value.new(token, :end, message)
    write(progress)

    state = clear_token_by_label(state, label)
    %{state | progress: progress}
  end

  defp write_work_done(%__MODULE__{} = state, label) do
    token = get_token(state, label)
    progress = Notifications.WorkDone.Progress.Create.new(token: token)
    Transport.write(progress)
  end

  defp write(%{token: token} = progress) when not is_nil(token) do
    progress |> Value.to_progress() |> Transport.write()
  end

  defp write(_), do: :ok

  defp clear_token_by_label(%__MODULE__{} = state, label) do
    token_by_label = Map.delete(state.token_by_label, label)
    %{state | token_by_label: token_by_label}
  end

  defp get_token_when_update(state, label) do
    case label do
      "mix compile" ->
        get_token(state, "mix compile") || get_token(state, "mix deps.compile")

      _ ->
        get_token(state, label)
    end
  end

  defp get_token(state, label) do
    state.token_by_label[label]
  end
end
