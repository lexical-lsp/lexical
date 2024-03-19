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

    with {:ok, prefix} <- fetch_conventional_prefix(relative_path),
         {:ok, new_name} <- fetch_new_name(entry, new_suffix) do
      extname = Path.extname(entry.path)
      suffix = Macro.underscore(new_name)
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

      {_module_path, prefix} ->
        prefix = prefix |> Enum.reverse() |> Enum.join("/")
        {:ok, prefix}
    end
  end
end
