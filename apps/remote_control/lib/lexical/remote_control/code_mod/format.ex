defmodule Lexical.RemoteControl.CodeMod.Format do
  alias Lexical.Document
  alias Lexical.Document.Changes
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.CodeMod.Diff

  require Logger

  @type formatter_function :: (String.t() -> any) | nil

  @spec edits(Project.t(), Document.t()) :: {:ok, Changes.t()} | {:error, any}
  def edits(%Project{} = project, %Document{} = document) do
    with :ok <- Build.compile_document(project, document),
         {:ok, unformatted, formatted} <- do_format(project, document) do
      edits = Diff.diff(unformatted, formatted)
      {:ok, Changes.new(document, edits)}
    end
  end

  defp do_format(%Project{} = project, %Document{} = document) do
    project_path = Project.project_path(project)

    with :ok <- check_current_directory(document, project_path),
         {:ok, formatter} <- formatter_for(project, document.path) do
      document
      |> Document.to_string()
      |> formatter.()
    end
  end

  @spec formatter_for(Project.t(), String.t()) :: {:ok, formatter_function}
  defp formatter_for(%Project{} = project, uri_or_path) do
    path = Document.Path.ensure_path(uri_or_path)
    formatter_function = formatter_for_file(project, path)
    wrapped_formatter_function = wrap_with_try_catch(formatter_function)
    {:ok, wrapped_formatter_function}
  end

  defp wrap_with_try_catch(formatter_fn) do
    fn code ->
      try do
        {:ok, code, formatter_fn.(code)}
      rescue
        e ->
          {:error, e}
      end
    end
  end

  defp check_current_directory(%Document{} = document, project_path) do
    if subdirectory?(document.path, parent: project_path) do
      :ok
    else
      message =
        """
        Cannot format file #{document.path}.
        It is not in the project at #{project_path}
        """
        |> String.trim()

      {:error, message}
    end
  end

  defp subdirectory?(child, parent: parent) do
    normalized_parent = Path.absname(parent)
    String.starts_with?(child, normalized_parent)
  end

  defp formatter_for_file(%Project{} = project, file_path) do
    fetch_formatter = fn -> Mix.Tasks.Format.formatter_for_file(file_path) end

    {formatter, _opts} =
      if RemoteControl.project_node?() do
        case RemoteControl.Mix.in_project(project, fn _ -> fetch_formatter.() end) do
          {:ok, result} ->
            result

          _ ->
            formatter = &Code.format_string!/1
            {formatter, nil}
        end
      else
        fetch_formatter.()
      end

    formatter
  end
end
