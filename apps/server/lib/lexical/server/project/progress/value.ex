defmodule Lexical.Server.Project.Progress.Value do
  alias Lexical.Protocol.Notifications
  alias Lexical.Protocol.Types.WorkDone

  @enforce_keys [:token, :kind]
  defstruct [:token, :kind, :title, :message]

  def new(token, :begin, title) do
    %__MODULE__{token: token, kind: :begin, title: title}
  end

  def new(token, kind, message) when kind in [:report, :end] do
    %__MODULE__{token: token, kind: kind, message: message}
  end

  def to_progress(%__MODULE__{kind: :report = kind} = value) do
    p_value = WorkDone.Progress.Report.new(kind: kind, message: value.message)
    Notifications.Progress.new(token: value.token, value: p_value)
  end

  def to_progress(%__MODULE__{kind: :begin = kind} = value) do
    p_value = WorkDone.Progress.Begin.new(kind: kind, title: value.title)
    Notifications.Progress.new(token: value.token, value: p_value)
  end

  def to_progress(%__MODULE__{kind: :end = kind} = value) do
    p_value = WorkDone.Progress.End.new(kind: kind, message: value.message)
    Notifications.Progress.new(token: value.token, value: p_value)
  end
end