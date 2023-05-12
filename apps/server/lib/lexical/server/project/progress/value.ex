defmodule Lexical.Server.Project.Progress.Value do
  alias Lexical.Protocol.Notifications
  alias Lexical.Protocol.Types.WorkDone

  @enforce_keys [:token, :kind]
  defstruct [:token, :kind, :title, :message]

  def begin(title) do
    token = System.unique_integer([:positive])
    %__MODULE__{token: token, kind: :begin, title: title}
  end

  def report(%__MODULE__{token: token}, message) do
    %__MODULE__{token: token, kind: :report, message: message}
  end

  def report(_, _) do
    nil
  end

  def complete(%__MODULE__{token: token}, message) do
    %__MODULE__{token: token, kind: :end, message: message}
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
