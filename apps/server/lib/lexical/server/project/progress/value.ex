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

  def to_protocol(%__MODULE__{kind: :begin} = value) do
    Notifications.Progress.new(
      token: value.token,
      value: WorkDone.Progress.Begin.new(kind: value.kind, title: value.title)
    )
  end

  def to_protocol(%__MODULE__{kind: :report} = value) do
    Notifications.Progress.new(
      token: value.token,
      value: WorkDone.Progress.Report.new(kind: value.kind, message: value.message)
    )
  end

  def to_protocol(%__MODULE__{kind: :end} = value) do
    Notifications.Progress.new(
      token: value.token,
      value: WorkDone.Progress.End.new(kind: value.kind, message: value.message)
    )
  end
end
