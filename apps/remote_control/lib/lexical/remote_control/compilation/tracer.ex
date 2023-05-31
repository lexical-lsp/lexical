defmodule Lexical.RemoteControl.Compilation.Tracer do
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Compilation

  import RemoteControl.Api.Messages

  def trace({:on_module, module_binary, _filename}, %Macro.Env{} = env) do
    message = extract_module_updated(env.module, module_binary, env.file)
    Compilation.Dispatch.dispatch(message)
    :ok
  end

  def trace(_event, _env) do
    :ok
  end

  def extract_module_updated(module, module_binary, filename) do
    unless Code.ensure_loaded?(module) do
      erlang_filename =
        filename
        |> ensure_filename()
        |> String.to_charlist()

      :code.load_binary(module, erlang_filename, module_binary)
    end

    functions = module.__info__(:functions)
    macros = module.__info__(:macros)

    struct =
      if function_exported?(module, :__struct__, 0) do
        module.__struct__()
        |> Map.from_struct()
        |> Enum.map(fn {k, v} ->
          %{field: k, required?: !is_nil(v)}
        end)
      end

    module_updated(
      file: filename,
      functions: functions,
      macros: macros,
      name: module,
      struct: struct
    )
  end

  defp ensure_filename(:none) do
    unique = System.unique_integer([:positive, :monotonic])
    Path.join(System.tmp_dir(), "file-#{unique}.ex")
  end

  defp ensure_filename(filename) when is_binary(filename) do
    filename
  end
end
