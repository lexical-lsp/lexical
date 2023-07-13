defmodule Mix.Tasks.Namespace.Transform.Apps do
  @moduledoc """
  Applies namespacing to all modules defined in .app files
  """
  alias Mix.Tasks.Namespace
  alias Mix.Tasks.Namespace.Transform

  def apply_to_all(base_directory) do
    base_directory
    |> find_app_files()
    |> tap(fn app_files ->
      Mix.Shell.IO.info("Rewriting #{length(app_files)} app files")
    end)
    |> Enum.each(&apply/1)
  end

  def apply(file_path) do
    with {:ok, app_definition} <- Transform.Erlang.path_to_term(file_path),
         {:ok, converted} <- convert(app_definition),
         :ok <- File.write(file_path, converted) do
      app_name =
        file_path
        |> Path.basename()
        |> Path.rootname()
        |> String.to_atom()

      namespaced_app_name = Namespace.Module.apply(app_name)
      new_filename = "#{namespaced_app_name}.app"

      new_file_path =
        file_path
        |> Path.dirname()
        |> Path.join(new_filename)

      File.rename!(file_path, new_file_path)
    end
  end

  defp find_app_files(base_directory) do
    app_files_glob = Enum.join(Namespace.app_names(), ",")

    [base_directory, "**", "{#{app_files_glob}}.app"]
    |> Path.join()
    |> Path.wildcard()
  end

  defp convert(app_definition) do
    erlang_terms =
      app_definition
      |> visit()
      |> Transform.Erlang.term_to_string()

    {:ok, erlang_terms}
  end

  defp visit({:application, app_name, keys}) do
    {:application, Namespace.Module.apply(app_name), Enum.map(keys, &visit/1)}
  end

  defp visit({:applications, app_list}) do
    {:applications, Enum.map(app_list, &Namespace.Module.apply/1)}
  end

  defp visit({:modules, module_list}) do
    {:modules, Enum.map(module_list, &Namespace.Module.apply/1)}
  end

  defp visit({:description, desc}) do
    {:description, desc ++ ' namespaced by lexical.'}
  end

  defp visit({:mod, {module_name, args}}) do
    {:mod, {Namespace.Module.apply(module_name), args}}
  end

  defp visit(key_value) do
    key_value
  end
end
