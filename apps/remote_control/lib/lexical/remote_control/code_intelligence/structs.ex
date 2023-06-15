defmodule Lexical.RemoteControl.CodeIntelligence.Structs do
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages

  import Messages

  def discover_deps_structs do
    if Mix.Project.get() do
      deps_projects()
    else
      RemoteControl.Mix.in_project(fn _ -> deps_projects() end)
    end
  end

  defp elixir_module?(module_name_charlist) when is_list(module_name_charlist) do
    List.starts_with?(module_name_charlist, 'Elixir.')
  end

  defp elixir_module?(module_atom) when is_atom(module_atom) do
    module_atom
    |> Atom.to_charlist()
    |> elixir_module?()
  end

  defp deps_projects do
    # This might be a performance / memory issue on larger projects. It
    # iterates through all modules, loading each as necessary and then removing them
    # if they're not already loaded to try and claw back some memory

    for dep_app <- Mix.Project.deps_apps(),
        module_name <- dep_modules(dep_app),
        elixir_module?(module_name),
        was_loaded? = :code.is_loaded(module_name),
        Code.ensure_loaded?(module_name) do
      case module_name.__info__(:struct) do
        struct_fields when is_list(struct_fields) ->
          message = struct_discovered(module: module_name, fields: struct_fields)
          RemoteControl.notify_listener(message)

        _ ->
          :ok
      end

      unless was_loaded? do
        :code.delete(module_name)
        :code.purge(module_name)
      end
    end
  end

  defp dep_modules(app_name) do
    case :application.get_key(app_name, :modules) do
      {:ok, modules} -> modules
      _ -> []
    end
  end
end
