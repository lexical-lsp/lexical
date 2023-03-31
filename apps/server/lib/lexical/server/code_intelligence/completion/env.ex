defmodule Lexical.Server.CodeIntelligence.Completion.Env do
  alias Lexical.Completion.Environment
  alias Lexical.Project
  alias Lexical.SourceFile
  alias Lexical.SourceFile.Position

  defstruct [:project, :document, :prefix, :suffix, :position, :words]

  @type t :: %__MODULE__{
          project: Lexical.Project.t(),
          document: Lexical.SourceFile.t(),
          prefix: String.t(),
          suffix: String.t(),
          position: Lexical.SourceFile.Position.t(),
          words: [String.t()]
        }

  @behaviour Environment

  def new(%Project{} = project, %SourceFile{} = document, %Position{} = cursor_position) do
    case SourceFile.fetch_text_at(document, cursor_position.line) do
      {:ok, line} ->
        graphemes = String.graphemes(line)
        prefix = graphemes |> Enum.take(cursor_position.character) |> IO.iodata_to_binary()
        suffix = String.slice(line, cursor_position.character..-1)
        words = String.split(prefix)

        {:ok,
         %__MODULE__{
           project: project,
           document: document,
           prefix: prefix,
           suffix: suffix,
           position: cursor_position,
           words: words
         }}

      _ ->
        {:error, :out_of_bounds}
    end
  end

  @impl Environment
  def function_capture?(%__MODULE__{} = env) do
    case cursor_context(env) do
      {:ok, line, {:alias, module_name}} ->
        # &Enum|
        String.contains?(line, List.to_string([?& | module_name]))

      {:ok, line, {:dot, {:alias, module_name}, _}} ->
        # &Enum.f|
        String.contains?(line, List.to_string([?& | module_name]))

      _ ->
        false
    end
  end

  @impl Environment
  def struct_reference?(%__MODULE__{} = env) do
    case cursor_context(env) do
      {:ok, _line, {:struct, _}} ->
        true

      {:ok, line, {:local_or_var, [?_, ?_ | rest]}} ->
        # a reference to `%__MODULE`, often in a function head, as in
        # def foo(%__)
        String.starts_with?("MODULE", List.to_string(rest)) and String.contains?(line, "%__")

      _ ->
        false
    end
  end

  @impl Environment
  def pipe?(%__MODULE__{} = env) do
    with {:ok, line, context} <- surround_context(env),
         {:ok, {:operator, '|>'}} <- previous_surround_context(line, context) do
      true
    else
      _ ->
        false
    end
  end

  @impl Environment
  def empty?("") do
    true
  end

  def empty?(string) when is_binary(string) do
    String.trim(string) == ""
  end

  @impl Environment
  def last_word(%__MODULE__{} = env) do
    List.last(env.words)
  end

  defp cursor_context(%__MODULE__{} = env) do
    with {:ok, line} <- SourceFile.fetch_text_at(env.document, env.position.line) do
      fragment = String.slice(line, 0..(env.position.character - 1))
      {:ok, line, Code.Fragment.cursor_context(fragment)}
    end
  end

  defp surround_context(%__MODULE__{} = env) do
    with {:ok, line} <- SourceFile.fetch_text_at(env.document, env.position.line),
         %{context: _} = context <-
           Code.Fragment.surround_context(line, {1, env.position.character}) do
      {:ok, line, context}
    end
  end

  defp previous_surround_context(line, %{begin: {1, column}}) do
    previous_surround_context(line, column)
  end

  defp previous_surround_context(_line, 1) do
    :error
  end

  defp previous_surround_context(line, character) when is_integer(character) do
    case Code.Fragment.surround_context(line, {1, character - 1}) do
      :none ->
        previous_surround_context(line, character - 1)

      %{context: context} ->
        {:ok, context}
    end
  end
end
