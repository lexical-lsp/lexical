defmodule Lexical.RemoteControl.CodeMod.Rename.File do
  alias Lexical.Ast
  alias Lexical.Document
  alias Lexical.ProcessCache
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.CodeIntelligence.Entity
  alias Lexical.RemoteControl.Search.Indexer
  alias Lexical.RemoteControl.Search.Indexer.Entry

  @spec maybe_rename(Document.t(), Entry.t(), String.t()) :: Document.Changes.rename_file()
  def maybe_rename(%Document{} = document, %Entry{} = entry, new_suffix) do
    if root_module?(entry, document) do
      rename_file(document, entry, new_suffix)
    end
  end

  defp root_module?(entry, document) do
    entries =
      ProcessCache.trans("#{document.uri}-entries", 50, fn ->
        with {:ok, entries} <-
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

  defp rename_file(document, entry, new_suffix) do
    root_path = root_path()
    relative_path = relative_path(entry.path, root_path)

    with {:ok, prefix} <- fetch_conventional_prefix(relative_path),
         {:ok, new_name} <- fetch_new_name(document, entry, new_suffix) do
      extname = Path.extname(entry.path)

      suffix =
        new_name
        |> Macro.underscore()
        |> maybe_insert_special_phoenix_folder(entry.subject, relative_path)

      new_path = Path.join([root_path, prefix, "#{suffix}#{extname}"])
      new_uri = Document.Path.ensure_uri(new_path)

      if document.uri != new_uri do
        Document.Changes.RenameFile.new(document.uri, new_uri)
      end
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

  defp fetch_new_name(document, entry, new_suffix) do
    text_edits = [Document.Edit.new(new_suffix, entry.range)]

    with {:ok, edited_document} <-
           Document.apply_content_changes(document, document.version + 1, text_edits),
         {:ok, %{context: {:alias, alias}}} <-
           Ast.surround_context(edited_document, entry.range.start) do
      {:ok, to_string(alias)}
    else
      _ -> :error
    end
  end

  defp fetch_conventional_prefix(path) do
    # To obtain the new relative path, we can't directly convert from the *new module* name.
    # We also need a part of the prefix, and Elixir has some conventions in this regard,
    # For example:
    #
    # in umbrella projects, the prefix is `Path.join(["apps", app_name, "lib"])`
    # in non-umbrella projects, most file's prefix is `"lib"`
    #
    # ## Examples
    #
    # iex> fetch_conventional_prefix("apps/remote_control/lib/lexical/remote_control/code_mod/rename/file.ex")
    # {:ok, "apps/remote_control/lib"}
    result =
      path
      |> Path.split()
      |> Enum.chunk_every(2, 2)
      |> Enum.reduce([], fn
        ["apps", app_name], _ ->
          [app_name, "apps"]

        ["lib", _follow_element], prefix ->
          ["lib" | prefix]

        ["test", _follow_element], prefix ->
          ["test" | prefix]

        _remain, prefix ->
          prefix
      end)

    case result do
      [] ->
        :error

      prefix ->
        prefix = prefix |> Enum.reverse() |> Path.join()
        {:ok, prefix}
    end
  end

  defp maybe_insert_special_phoenix_folder(suffix, subject, relative_path) do
    insertions =
      cond do
        Entity.phoenix_controller_module?(subject) ->
          "controllers"

        Entity.phoenix_liveview_module?(subject) ->
          "live"

        Entity.phoenix_component_module?(subject) ->
          "components"

        true ->
          nil
      end

    # In some cases, users prefer to include the `insertions` in the module name,
    # such as `DemoWeb.Components.Icons`.
    # In this case, we should not insert the prefix in a nested manner.
    prefer_to_include_insertions? = insertions && insertions in Path.split(suffix)
    old_path_contains_insertions? = insertions in Path.split(relative_path)

    if not is_nil(insertions) and old_path_contains_insertions? and
         not prefer_to_include_insertions? do
      suffix
      |> Path.split()
      |> List.insert_at(1, insertions)
      |> Enum.reject(&(&1 == ""))
      |> Path.join()
    else
      suffix
    end
  end
end
