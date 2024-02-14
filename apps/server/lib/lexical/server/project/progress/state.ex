defmodule Lexical.Server.Project.Progress.State do
  alias Lexical.Project
  alias Lexical.Protocol.Id
  alias Lexical.Protocol.Requests
  alias Lexical.Server.Configuration
  alias Lexical.Server.Project.Progress.Percentage
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

    %__MODULE__{state | progress_by_label: progress_by_label}
  end

  def begin(%__MODULE__{} = state, percent_progress(label: label, max: max)) do
    progress = Percentage.begin(label, max)
    progress_by_label = Map.put(state.progress_by_label, label, progress)
    write_work_done(progress.token)
    write(progress)

    %__MODULE__{state | progress_by_label: progress_by_label}
  end

  def report(%__MODULE__{} = state, project_progress(label: label, message: message)) do
    {progress, progress_by_label} =
      Map.get_and_update(state.progress_by_label, label, fn old_value ->
        new_value = Value.report(old_value, message)
        {new_value, new_value}
      end)

    write(progress)
    %__MODULE__{state | progress_by_label: progress_by_label}
  end

  def report(
        %__MODULE__{} = state,
        percent_progress(label: label, message: message, delta: delta)
      ) do
    {progress, progress_by_label} =
      Map.get_and_update(state.progress_by_label, label, fn old_percentage ->
        new_percentage = Percentage.report(old_percentage, delta, message)
        {new_percentage, new_percentage}
      end)

    write(progress)
    %__MODULE__{state | progress_by_label: progress_by_label}
  end

  def complete(%__MODULE__{} = state, project_progress(label: label, message: message)) do
    {progress, progress_by_label} =
      Map.get_and_update(state.progress_by_label, label, fn _ -> :pop end)

    case progress do
      %Value{} = progress ->
        progress |> Value.complete(message) |> write

      _ ->
        :ok
    end

    %__MODULE__{state | progress_by_label: progress_by_label}
  end

  def complete(%__MODULE__{} = state, percent_progress(label: label, message: message)) do
    {progress, progress_by_label} =
      Map.get_and_update(state.progress_by_label, label, fn _ -> :pop end)

    case progress do
      %Percentage{} = progress ->
        progress |> Percentage.complete(message) |> write()

      nil ->
        :ok
    end

    %__MODULE__{state | progress_by_label: progress_by_label}
  end

  defp write_work_done(token) do
    if Configuration.client_supports?(:work_done_progress) do
      progress = Requests.CreateWorkDoneProgress.new(id: Id.next(), token: token)
      Transport.write(progress)
    end
  end

  defp write(%progress_module{token: token} = progress) when not is_nil(token) do
    if Configuration.client_supports?(:work_done_progress) do
      progress |> progress_module.to_protocol() |> Transport.write()
    end
  end

  defp write(_), do: :ok
end
