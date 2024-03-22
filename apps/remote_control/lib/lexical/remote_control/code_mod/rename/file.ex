defmodule Lexical.RemoteControl.CodeMod.Rename.File do
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.ProcessCache
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Search.Indexer
  alias Lexical.RemoteControl.Search.Indexer.Entry

  @spec maybe_rename(Entry.t(), String.t()) :: Document.Changes.rename_file()
  def maybe_rename(entry, new_suffix) do
    if root_module?(entry) do
      rename_file(entry, new_suffix)
    end
  end

  defp root_module?(entry) do
    uri = Document.Path.ensure_uri(entry.path)

    entries =
      ProcessCache.trans("#{uri}-entries", 50, fn ->
        with {:ok, document} <- Document.Store.open_temporary(uri),
             {:ok, entries} <-
               Indexer.Source.index_document(document, [Indexer.Extractors.Module]) do
          entries
        end
      end)

    case Enum.filter(entries, &(&1.block_id == :root)) do
      [root_module] ->
        root_module.subject == entry.subject and root_module.block_range == entry.block_range

      _ ->
        false
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

      old_uri = Document.Path.ensure_uri(entry.path)
      new_uri = Document.Path.ensure_uri(new_path)
      Document.Changes.RenameFile.new(old_uri, new_uri)
    else
      _ -> nil
    end
  end

  defp relative_path(path, root_path) do
    Path.relative_to(path, root_path)
  end

  defp root_path do
    Project.root_path(RemoteControl.get_project())
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
