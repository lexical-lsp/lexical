defmodule Lexical.Server.Project.Progress do
  require Logger

  defmodule ProgressValue do
    defstruct [:title, :message, :percentage]

    def new(options) do
      %__MODULE__{
        title: options[:title],
        message: options[:message],
        percentage: options[:percentage]
      }
    end
  end

  defmodule State do
    defstruct [
      :project,
      :token_by_label,
      :percentages_by_label,
      :progress
    ]

    def new(project) do
      %__MODULE__{
        project: project,
        progress: nil,
        token_by_label: %{},
        percentages_by_label: %{}
      }
    end

    @prepare_labels ~w(local.hex.begin local.hex.end local.rebar.begin local.rebar.end deps.get.begin deps.get.end)s
    @compile_labels ~w(deps.compile.begin deps.compile deps.compile.end compile.begin compile compile.end)s

    @mix_labels @prepare_labels ++ @compile_labels

    def add(state, label, message \\ "") do
      # Only need to care about `begin` and `report` events
      # `end` event is too simple

      case kind(label) do
        "prepare" ->
          percentages =
            Map.put(state.percentages_by_label, trim(label), %{
              percentage: 0,
              total: message,
              finished: %{}
            })

          %{state | percentages_by_label: percentages}

        "begin" ->
          token = System.unique_integer([:positive])
          progress = ProgressValue.new(title: title(label))

          %{
            state
            | token_by_label: Map.put(state.token_by_label, trim(label), token),
              progress: progress
          }

        _ ->
          # TODO: refactor and reduce complexity
          percentages_by_label = percentages(state, label, message)
          state = %{state | percentages_by_label: percentages_by_label}
          progress = report_progress(state, label, message)
          %{state | progress: progress}
      end
    end

    defp percentages(state, "compile", file) do
      Logger.info("compile state: #{inspect(state)}")

      total = state.percentages_by_label["compile"].total
      finished = state.percentages_by_label["compile"].finished
      finished? = Map.has_key?(finished, file)

      if not finished? do
        finished = Map.put(finished, file, true)

        %{
          "compile" => %{
            total: total,
            finished: finished,
            percentage: trunc(map_size(finished) * 100 / total)
          }
        }
      else
        state.percentages_by_label
      end
    end

    defp percentages(state, _, _) do
      state.percentages_by_label
    end

    defp report_progress(state, label, message) do
      case trim(label) do
        "compile" ->
          compile_report_progress(state, message)

        _ ->
          ProgressValue.new(message: message)
      end
    end

    defp compile_report_progress(state, message) do
      case state.percentages_by_label["compile"] do
        nil ->
          nil

        _ ->
          ProgressValue.new(
            message: message,
            percentage: state.percentages_by_label["compile"].percentage
          )
      end
    end

    def trim(label) do
      label
      |> String.trim_trailing(".begin")
      |> String.trim_trailing(".end")
      |> String.trim_trailing(".prepare")
    end

    def kind(label) do
      kind = String.split(label, ".") |> List.last()
      if kind in ["prepare", "begin", "end"], do: kind, else: "report"
    end

    defp title(label) when label in @mix_labels do
      "mix " <> trim(label)
    end

    defp title(label) do
      trim(label)
    end
  end

  alias Lexical.Project
  alias Lexical.Protocol.Notifications.CreateWorkDoneProgress
  alias Lexical.Protocol.Notifications.Progress, as: LSProgress
  alias Lexical.Protocol.Types.WorkDone.ProgressBegin
  alias Lexical.Protocol.Types.WorkDone.Progress.Report, as: ProgressReport
  alias Lexical.Protocol.Types.WorkDone.ProgressEnd
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.Server.Project.Dispatch
  alias Lexical.Server.Transport

  require Logger

  import Messages

  use GenServer

  def start_link(%Project{} = project) do
    GenServer.start_link(__MODULE__, [project], name: name(project))
  end

  def child_spec(%Project{} = project) do
    %{
      id: {__MODULE__, Project.name(project)},
      start: {__MODULE__, :start_link, [project]}
    }
  end

  # GenServer callbacks

  @impl GenServer
  def init([project]) do
    Dispatch.register(project, [project_progress()])
    {:ok, State.new(project)}
  end

  @impl true
  def handle_info(project_progress(label: label, message: message), %State{} = state) do
    Logger.info("label is #{label}, message is #{message}")
    state = State.add(state, label, message)

    case State.kind(label) do
      "begin" ->
        create_workdone_progress(state, label)
        begin_progress(state, label)

      "end" ->
        end_progress(state, label)

      _ ->
        report_progress(state, label)
    end

    {:noreply, state}
  end

  defp name(%Project{} = project) do
    :"#{Project.name(project)}::progress"
  end

  defp create_workdone_progress(state, label) do
    token = get_token(state, label)
    progress = CreateWorkDoneProgress.new(token: token)
    Transport.write(progress)
  end

  defp begin_progress(state, label) do
    token = get_token(state, label)
    value = to_progress_begin(state)
    progress = LSProgress.new(token: token, value: value)
    Transport.write(progress)
  end

  defp report_progress(state, label) do
    token = get_token(state, label)
    value = to_progress_report(state)

    if token && value do
      progress = LSProgress.new(token: token, value: value)
      Transport.write(progress)
    end
  end

  defp end_progress(state, label) do
    token = get_token(state, label)
    value = ProgressEnd.new(kind: "end")
    progress = LSProgress.new(token: token, value: value)
    Transport.write(progress)
  end

  defp to_progress_begin(%State{progress: progress}) do
    ProgressBegin.new(kind: "begin", title: progress.title)
  end

  defp to_progress_report(%State{progress: nil}) do
    # NOTE: we need to use nil to ignore prepare progress
    # and some incorrect progress like `compile` without percentage
    nil
  end

  defp to_progress_report(%State{progress: progress}) do
    ProgressReport.new(
      kind: "report",
      message: progress.message,
      percentage: progress.percentage
    )
  end

  defp get_token(state, label) do
    Map.get(state.token_by_label, State.trim(label))
  end
end
