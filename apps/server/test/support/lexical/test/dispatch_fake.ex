defmodule Lexical.Test.DispatchFake do
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Dispatch

  defmacro __using__(_) do
    quote do
      require unquote(__MODULE__)
    end
  end

  # This is a macro because patch requires that you're in a unit test, and have a setup block
  # We need to defer the patch macros until we get inside a unit test context, and the macro
  # does that for us.
  defmacro start do
    quote do
      patch(RemoteControl.Api, :register_listener, fn _project, listener_pid, message_types ->
        Dispatch.register_listener(listener_pid, message_types)
      end)

      patch(RemoteControl.Api, :broadcast, fn _project, message ->
        Dispatch.broadcast(message)
      end)

      patch(Dispatch, :register_progress_listener, :ok)

      start_supervised!(Dispatch)
    end
  end
end
