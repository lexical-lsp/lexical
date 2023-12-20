defmodule Lexical.Server.Project.Progress.Percentage do
  @moduledoc """
  The backing data structure for percentage based progress reports
  """
  alias Lexical.Math
  alias Lexical.Protocol.Notifications
  alias Lexical.Protocol.Types.WorkDone

  @enforce_keys [:token, :kind, :max]
  defstruct [:token, :kind, :title, :message, :max, current: 0]

  def begin(title, max) do
    token = System.unique_integer([:positive])
    %__MODULE__{token: token, kind: :begin, title: title, max: max}
  end

  def report(percentage, delta, message \\ "")

  def report(%__MODULE__{} = percentage, delta, message) when is_integer(delta) and delta >= 0 do
    new_current = percentage.current + delta

    %__MODULE__{percentage | kind: :report, message: message, current: new_current}
  end

  def report(%__MODULE__{} = percentage, delta, _message) when is_integer(delta) do
    percentage
  end

  def report(_, _, _) do
    nil
  end

  def complete(%__MODULE__{} = percentage, message) do
    %__MODULE__{percentage | kind: :end, current: percentage.max, message: message}
  end

  def to_protocol(%__MODULE__{kind: :begin} = value) do
    Notifications.Progress.new(
      token: value.token,
      value: WorkDone.Progress.Begin.new(kind: "begin", title: value.title, percentage: 0)
    )
  end

  def to_protocol(%__MODULE__{kind: :report} = value) do
    percent_complete =
      (value.current / value.max * 100)
      |> round()
      |> Math.clamp(0, 100)

    Notifications.Progress.new(
      token: value.token,
      value:
        WorkDone.Progress.Report.new(
          kind: "report",
          message: value.message,
          percentage: percent_complete
        )
    )
  end

  def to_protocol(%__MODULE__{kind: :end} = value) do
    Notifications.Progress.new(
      token: value.token,
      value: WorkDone.Progress.End.new(kind: "end", message: value.message)
    )
  end
end
