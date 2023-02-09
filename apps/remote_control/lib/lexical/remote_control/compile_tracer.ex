defmodule Lexical.RemoteControl.CompileTracer do
  alias Lexical.RemoteControl

  import RemoteControl.Api.Messages

  def trace({:on_module, _, _}, env) do
    message = extract_module_updated(env.module)
    RemoteControl.notify_listener(message)
    :ok
  end

  def trace(_event, _env) do
    :ok
  end

  def extract_module_updated(module) do
    functions = module.__info__(:functions)
    macros = module.__info__(:macros)
    struct = module.__info__(:struct)

    module_updated(
      name: module,
      functions: functions,
      macros: macros,
      struct: struct
    )
  end
end
