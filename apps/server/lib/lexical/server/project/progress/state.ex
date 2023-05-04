defmodule Lexical.Server.Project.Progress.State do
  alias Lexical.Project
  alias Lexical.Protocol.Notifications
  alias Lexical.Server.Project.Progress.Value
  alias Lexical.Server.Transport

  require Logger

  defstruct [
    :project,
    :token_by_label,
    :progress
  ]

  def new(%Project{} = project) do
    %__MODULE__{
      project: project,
      token_by_label: %{},
      progress: nil
    }
  end

  def begin(%__MODULE__{} = state, label) do
    token = System.unique_integer([:positive])
    token_by_label = Map.put(state.token_by_label, trim(label), token)

    state = %{state | token_by_label: token_by_label}
    create_workdone_progress(state, label)

    progress = begin_progress_value(label, token)
    send_progress(progress)

    %{state | progress: progress}
  end

  def update(%__MODULE__{} = state, label, message) do
    progress = report_progress_value(state, label, message)
    send_progress(progress)
    %{state | progress: progress}
  end

  def complete(%__MODULE__{} = state, label, message \\ "") do
    progress = end_progress_value(state, label, message)
    send_progress(progress)

    state = clear_token_by_label(state, label)
    %{state | progress: progress}
  end

  def trim(label) do
    label
    |> String.trim_trailing(".prepare")
    |> String.trim_trailing(".begin")
    |> String.trim_trailing(".end")
  end

  def kind(label) do
    kind = String.split(label, ".") |> List.last()
    if kind in ["prepare", "begin", "end"], do: String.to_atom(kind), else: :report
  end

  defp create_workdone_progress(%__MODULE__{} = state, label) do
    token = get_token(state, label)
    progress = Notifications.CreateWorkDoneProgress.new(token: token)
    Transport.write(progress)
  end

  defp send_progress(progress) do
    if progress.token do
      progress |> Value.to_progress() |> Transport.write()
    end
  end

  defp begin_progress_value(label, token) do
    Value.new(kind: kind(label), token: token, title: trim(label))
  end

  defp report_progress_value(state, label, message) do
    token = get_token_when_update(state, label)
    Value.new(kind: kind(label), token: token, message: message)
  end

  defp end_progress_value(state, label, message) do
    token = get_token(state, label)
    Value.new(kind: kind(label), token: token, message: message)
  end

  defp clear_token_by_label(%__MODULE__{} = state, label) do
    token_by_label = Map.delete(state.token_by_label, trim(label))
    %{state | token_by_label: token_by_label}
  end

  defp get_token_when_update(state, label) do
    case trim(label) do
      "mix compile" ->
        # NOTE: `mix compile` updating event is from the compile tracer
        # Then this tracer can be triggered by both `mix deps.compile` and `mix compile`.
        get_token(state, "mix compile") || get_token(state, "mix deps.compile")

      _ ->
        get_token(state, label)
    end
  end

  defp get_token(state, label) do
    state.token_by_label[trim(label)]
  end
end
