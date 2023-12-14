defmodule Lexical.RemoteControl.Progress do
  alias Lexical.RemoteControl.Dispatch
  import Lexical.RemoteControl.Api.Messages

  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__), only: [with_progress: 2]
    end
  end

  def with_progress(label, func) when is_function(func, 0) do
    try do
      Dispatch.broadcast(project_progress(label: label, stage: :begin))
      func.()
    after
      Dispatch.broadcast(project_progress(label: label, stage: :complete))
    end
  end

  def with_percent_progress(label, max, func) when is_function(func, 1) do
    report_progress = fn delta, message ->
      Dispatch.broadcast(
        percent_progress(label: label, message: message, delta: delta, stage: :report)
      )
    end

    try do
      Dispatch.broadcast(percent_progress(label: label, max: max, stage: :begin))
      func.(report_progress)
    after
      Dispatch.broadcast(percent_progress(label: label, stage: :complete))
    end
  end
end
