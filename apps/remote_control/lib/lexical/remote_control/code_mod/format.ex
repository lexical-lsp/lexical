defmodule Lexical.RemoteControl.CodeMod.Format do
  alias Lexical.Document
  alias Lexical.Document.Changes
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.CodeMod.Diff

  require Logger

  @type formatter_function :: (String.t() -> any) | nil

  @spec edits(Document.t()) :: {:ok, Changes.t()} | {:error, any}
  def edits(%Document{} = document) do
    project = RemoteControl.get_project()

    with :ok <- Build.compile_document(project, document),
         {:ok, formatted} <- do_format(project, document) do
      edits = Diff.diff(document, formatted)
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
        {:ok, formatter_fn.(code)}
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
    fetch_formatter = fn _ -> Mix.Tasks.Format.formatter_for_file(file_path) end

    {formatter, _opts} =
      if RemoteControl.project_node?() do
        case RemoteControl.Mix.in_project(project, fetch_formatter) do
          {:ok, result} ->
            result

          _error ->
            formatter_opts =
              case find_formatter_exs(project, file_path) do
                {:ok, opts} ->
                  opts

                :error ->
                  Logger.warning("Could not find formatter options for file #{file_path}")
                  []
              end

            formatter = fn source ->
              formatted_source = Code.format_string!(source, formatter_opts)
              IO.iodata_to_binary([formatted_source, ?\n])
            end

            {formatter, nil}
        end
      else
        fetch_formatter.(nil)
      end

    formatter
  end

  defp find_formatter_exs(%Project{} = project, file_path) do
    root_dir = Project.root_path(project)
    do_find_formatter_exs(root_dir, file_path)
  end

  defp do_find_formatter_exs(root_path, root_path) do
    formatter_exs_contents(root_path)
  end

  defp do_find_formatter_exs(root_path, current_path) do
    with :error <- formatter_exs_contents(current_path) do
      parent =
        current_path
        |> Path.join("..")
        |> Path.expand()

      do_find_formatter_exs(root_path, parent)
    end
  end

  defp formatter_exs_contents(current_path) do
    formatter_exs = Path.join(current_path, ".formatter.exs")

    with true <- File.exists?(formatter_exs),
         {formatter_terms, _binding} <- Code.eval_file(formatter_exs) do
      Logger.info("found formatter in #{current_path}")
      {:ok, formatter_terms}
    else
      err ->
        Logger.info("No formatter found in #{current_path} error was #{inspect(err)}")

        :error
    end
  end
end
