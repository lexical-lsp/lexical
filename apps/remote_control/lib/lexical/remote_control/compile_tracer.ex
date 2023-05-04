defmodule Lexical.RemoteControl.CompileTracer do
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.ModuleMappings

  import RemoteControl.Api.Messages
  require Logger

  def trace({:on_module, _, _}, %Macro.Env{} = env) do
    message = extract_module_updated(env.module)

    ModuleMappings.update(env.module, env.file)
    RemoteControl.notify_listener(message)
    maybe_report_progress(env.file)

    :ok
  end

  def trace(_event, _env) do
    :ok
  end

  defp maybe_report_progress(file) do
    if Path.extname(file) == ".ex" do
      progress_message = progress_message(file)
      RemoteControl.notify_listener(progress_message)
    end
  end

  defp progress_message(file) do
    relative_path = Path.relative_to_cwd(file)

    if String.starts_with?(relative_path, "deps") do
      project_progress(label: "mix deps.compile", message: relative_path)
    else
      project_progress(label: "mix compile", message: relative_path)
    end
  end

  def extract_module_updated(module) do
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
      name: module,
      functions: functions,
      macros: macros,
      struct: struct
    )
  end
end
