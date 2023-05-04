defmodule Lexical.RemoteControl.Build.Progress do
  alias Lexical.RemoteControl

  import Lexical.RemoteControl.Api.Messages

  def with_progress(label, func, opts \\ []) when is_function(func) do
    mix? = Keyword.get(opts, :mix?, true)
    label = if mix?, do: "mix " <> label, else: label

    RemoteControl.notify_listener(project_progress(label: label <> ".begin"))
    result = func.()
    RemoteControl.notify_listener(project_progress(label: label <> ".end"))

    result
  end
end
