defmodule Lexical.Server.Project.Progress.State do
  alias Lexical.Project
  alias Lexical.Protocol.Id
  alias Lexical.Protocol.Requests
  alias Lexical.Server.Project.Progress.Value
  alias Lexical.Server.Transport

  import Lexical.RemoteControl.Api.Messages

  defstruct project: nil, progress_by_label: %{}

  def new(%Project{} = project) do
    %__MODULE__{project: project}
  end

  def begin(%__MODULE__{} = state, project_progress(label: label)) do
    progress = Value.begin(label)
    progress_by_label = Map.put(state.progress_by_label, label, progress)

    write_work_done(progress.token)
    write(progress)

    %{state | progress_by_label: progress_by_label}
  end

  def report(%__MODULE__{} = state, project_progress(label: label, message: message)) do
    {progress, progress_by_label} =
      Map.get_and_update(state.progress_by_label, label, fn old_value ->
        new_value = Value.report(old_value, message)
        {new_value, new_value}
      end)

    write(progress)
    %{state | progress_by_label: progress_by_label}
  end

  def complete(%__MODULE__{} = state, project_progress(label: label, message: message)) do
    {progress, progress_by_label} =
      Map.get_and_update(state.progress_by_label, label, fn _ -> :pop end)

    progress |> Value.complete(message) |> write()
    %{state | progress_by_label: progress_by_label}
  end

  defp write_work_done(token) do
    progress = Requests.CreateWorkDoneProgress.new(id: Id.next_request_id(), token: token)
    Transport.write(progress)
  end

  defp write(%{token: token} = progress) when not is_nil(token) do
    progress |> Value.to_protocol() |> Transport.write()
  end

  defp write(_), do: :ok
end
