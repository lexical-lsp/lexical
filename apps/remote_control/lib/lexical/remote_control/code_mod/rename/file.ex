defmodule Lexical.RemoteControl.CodeMod.Rename.File do
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Search.Store

  def maybe_rename(entry, new_suffix) do
    with false <- has_parent?(entry),
         false <- has_any_siblings?(entry) do
      rename_file(entry, new_suffix)
    else
      _ -> nil
    end
  end

  defp has_parent?(entry) do
    case Store.parent(entry) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp has_any_siblings?(entry) do
    case Store.siblings(entry) do
      {:ok, [_]} -> false
      {:ok, [_ | _]} -> true
      _ -> false
    end
  end

  defp rename_file(entry, new_suffix) do
    root_path = root_path()
    relative_path = relative_path(entry.path, root_path)

    with {:ok, prefix, old_module_paths} <- fetch_conventional_prefix(relative_path),
         {:ok, new_name} <- fetch_new_name(entry, new_suffix) do
      extname = Path.extname(entry.path)

      suffix =
        new_name
        |> Macro.underscore()
        |> maybe_insert_special_phoenix_folder(old_module_paths, new_name)

      new_path = Path.join([root_path, prefix, "#{suffix}#{extname}"])

      {Document.Path.ensure_uri(entry.path), Document.Path.ensure_uri(new_path)}
    else
      _ -> nil
    end
  end

  defp relative_path(path, root_path) do
    Path.relative_to(path, root_path)
  end

  defp root_path do
    RemoteControl.get_project()
    |> Map.get(:root_uri)
    |> Document.Path.ensure_path()
  end

  defp fetch_new_name(entry, new_suffix) do
    uri = Document.Path.ensure_uri(entry.path)
    text_edits = [Document.Edit.new(new_suffix, entry.range)]

    with {:ok, document} <- Document.Store.open_temporary(uri),
         {:ok, edited_document} =
           Document.apply_content_changes(document, document.version + 1, text_edits),
         {:ok, %{context: {:alias, alias}}} <-
           Ast.surround_context(edited_document, entry.range.start) do
      {:ok, to_string(alias)}
    else
      _ -> :error
    end
  end

  defp fetch_conventional_prefix(path) do
    result =
      path
      |> Path.split()
      |> Enum.chunk_every(2, 2)
      |> Enum.reduce({[], []}, fn
        ["apps", app_name], _ ->
          {[], [app_name, "apps"]}

        ["lib", follow_element], {elements, prefix} ->
          {[follow_element | elements], ["lib" | prefix]}

        ["test", follow_element], {elements, prefix} ->
          {[follow_element | elements], ["test" | prefix]}

        remain, {elements, prefix} ->
          {remain ++ elements, prefix}
      end)

    case result do
      {_, []} ->
        :error

      {module_paths, prefix} ->
        prefix = prefix |> Enum.reverse() |> Enum.join("/")
        {:ok, prefix, module_paths}
    end
  end

  defp maybe_insert_special_phoenix_folder(suffix, old_module_paths, new_name) do
    web_app? = new_name |> String.split(".") |> hd() |> String.ends_with?("Web")

    insertions =
      cond do
        not web_app? ->
          ""

        phoenix_component?(old_module_paths, new_name) ->
          "components"

        phoenix_controller?(old_module_paths, new_name) ->
          "controllers"

        phoenix_live_view?(old_module_paths, new_name) ->
          "live"

        true ->
          ""
      end

    suffix
    |> String.split("/")
    |> List.insert_at(1, insertions)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("/")
  end

  defp phoenix_component?(old_module_paths, new_name) do
    under_components? = "components" in old_module_paths
    component? = String.ends_with?(new_name, ["Components", "Layouts", "Component"])

    under_components? and component?
  end

  defp phoenix_controller?(old_module_paths, new_name) do
    under_controllers? = "controllers" in old_module_paths
    controller? = String.ends_with?(new_name, ["Controller", "JSON", "HTML"])

    under_controllers? and controller?
  end

  defp phoenix_live_view?(old_module_paths, new_name) do
    under_live_views? = "live" in old_module_paths
    new_name_list = String.split(new_name, ".")

    live_view? =
      if match?([_, _ | _], new_name_list) do
        parent = Enum.at(new_name_list, -2)
        local_module = Enum.at(new_name_list, -1)

        # `LiveDemoWeb.SomeLive` or `LiveDemoWeb.SomeLive.Index`
        String.ends_with?(parent, "Live") or String.ends_with?(local_module, "Live")
      else
        false
      end

    under_live_views? and live_view?
  end
end
