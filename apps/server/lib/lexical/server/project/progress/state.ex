defmodule Lexical.Server.Project.Progress.State do
  alias Lexical.Project
  alias Lexical.Protocol.Notifications
  alias Lexical.Server.Project.Progress.Value
  alias Lexical.Server.Transport

  import Lexical.RemoteControl.Api.Messages

  defstruct project: nil, progress_by_label: %{}

  def new(%Project{} = project) do
    %__MODULE__{project: project}
  end

  def begin(%__MODULE__{} = state, project_progress(label: label)) do
    token = System.unique_integer([:positive])
    progress = Value.new(token, :begin, label)
    progress_by_label = Map.put(state.progress_by_label, label, progress)

    write_work_done(token)
    write(progress)

    %{state | progress_by_label: progress_by_label}
  end

  def report(%__MODULE__{} = state, project_progress(label: label, message: message)) do
    token = get_token(state, label)

    progress = Value.new(token, :report, message)
    write(progress)

    progress_by_label = Map.put(state.progress_by_label, label, progress)
    %{state | progress_by_label: progress_by_label}
  end

  def complete(%__MODULE__{} = state, project_progress(label: label, message: message)) do
    token = get_token(state, label)

    progress = Value.new(token, :end, message)
    write(progress)

    clear_progress_by_label(state, label)
  end

  defp write_work_done(token) do
    progress = Notifications.WorkDone.Progress.Create.new(token: token)
    Transport.write(progress)
  end

  defp write(%{token: token} = progress) when not is_nil(token) do
    progress |> Value.to_progress() |> Transport.write()
  end

  defp write(_), do: :ok

  defp clear_progress_by_label(%__MODULE__{} = state, label) do
    progress_by_label = Map.delete(state.progress_by_label, label)
    %{state | progress_by_label: progress_by_label}
  end

  defp get_token(state, label) do
   get_in(state.progress_by_label, [label, :token])
  end
end
