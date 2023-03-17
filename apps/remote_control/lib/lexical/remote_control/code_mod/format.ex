defmodule Lexical.Server.CodeMod.Format do
  alias Lexical.Server.CodeMod.Diff
  alias Lexical.Project
  alias Lexical.Protocol.Types.TextEdit
  alias Lexical.RemoteControl
  alias Lexical.SourceFile

  require Logger
  @type formatter_function :: (String.t() -> any) | nil

  @spec text_edits(Project.t(), SourceFile.t()) :: {:ok, [TextEdit.t()]} | {:error, any}
  def text_edits(%Project{} = project, %SourceFile{} = document) do
    with :ok <- RemoteControl.Api.compile_source_file(project, document),
         {:ok, unformatted, formatted} <- do_format(project, document) do
      edits = Diff.diff(unformatted, formatted)
      {:ok, edits}
    end
  end

  @spec format(SourceFile.t()) :: {:ok, String.t()} | {:error, any}
  def format(%SourceFile{} = document) do
    with {:ok, _, formatted_code} <- do_format(document) do
      {:ok, formatted_code}
    end
  end

  defp do_format(%Project{} = project, %SourceFile{} = document) do
    project_path = Project.project_path(project)

    with :ok <- check_current_directory(document, project_path),
         {:ok, formatter, options} <- formatter_for(project, document.path),
         :ok <-
           check_inputs_apply(document, project_path, Keyword.get(options, :inputs)) do
      document
      |> SourceFile.to_string()
      |> formatter.()
    end
  end

  defp do_format(%SourceFile{} = document) do
    formatter = build_formatter([])

    document
    |> SourceFile.to_string()
    |> formatter.()
  end

  @spec formatter_for(Project.t(), String.t()) ::
          {:ok, formatter_function, keyword()} | {:error, :no_formatter_available}
  defp formatter_for(%Project{} = project, uri_or_path) do
    path = SourceFile.Path.ensure_path(uri_or_path)

    case RemoteControl.Api.formatter_for_file(project, path) do
      {:ok, formatter_function, options} ->
        wrapped_formatter_function = wrap_with_try_catch(formatter_function)
        {:ok, wrapped_formatter_function, options}

      _ ->
        options = RemoteControl.Api.formatter_options_for_file(project, path)
        formatter = build_formatter(options)
        {:ok, formatter, options}
    end
  end

  defp build_formatter(opts) do
    fn code ->
      formatted_iodata = Code.format_string!(code, opts)
      IO.iodata_to_binary([formatted_iodata, ?\n])
    end
    |> wrap_with_try_catch()
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

  defp check_current_directory(%SourceFile{} = document, project_path) do
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

  defp check_inputs_apply(%SourceFile{} = document, project_path, inputs)
       when is_list(inputs) do
    formatter_dir = dominating_formatter_exs_dir(document, project_path)

    inputs_apply? =
      Enum.any?(inputs, fn input_glob ->
        glob =
          if Path.type(input_glob) == :relative do
            Path.join(formatter_dir, input_glob)
          else
            input_glob
          end

        PathGlob.match?(document.path, glob, match_dot: true)
      end)

    if inputs_apply? do
      :ok
    else
      {:error, :input_mismatch}
    end
  end

  defp check_inputs_apply(_, _, _), do: :ok

  defp subdirectory?(child, parent: parent) do
    normalized_parent = Path.absname(parent)
    String.starts_with?(child, normalized_parent)
  end

  # Finds the directory with the .formatter.exs that's the nearest parent to the
  # source file, or the project dir if none was found.
  defp dominating_formatter_exs_dir(%SourceFile{} = document, project_path) do
    document.path
    |> Path.dirname()
    |> dominating_formatter_exs_dir(project_path)
  end

  defp dominating_formatter_exs_dir(project_dir, project_dir) do
    project_dir
  end

  defp dominating_formatter_exs_dir(current_dir, project_path) do
    formatter_exs_name = Path.join(current_dir, ".formatter.exs")

    if File.exists?(formatter_exs_name) do
      current_dir
    else
      current_dir
      |> Path.dirname()
      |> dominating_formatter_exs_dir(project_path)
    end
  end
end
