defmodule Lexical.RemoteControl.Build.Progress do
  alias Lexical.RemoteControl
  import Lexical.RemoteControl.Api.Messages

  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__), only: [with_progress: 2]
    end
  end

  def with_progress(label, func) when is_function(func, 0) do
    try do
      RemoteControl.notify_listener(project_progress(label: label, stage: :begin))
      func.()
    after
      RemoteControl.notify_listener(project_progress(label: label, stage: :complete))
    end
  end
end
