defmodule Lexical.RemoteControl.CompileTracer do
  alias Lexical.RemoteControl

  import RemoteControl.Messages

  def trace({:on_module, _, _}, env) do
    functions = env.module.__info__(:functions)
    macros = env.module.__info__(:macros)
    message = module_updated(name: env.module, functions: functions, macros: macros)
    RemoteControl.notify_listener(message)
    :ok
  end

  def trace(_event, _env) do
    :ok
  end
end
