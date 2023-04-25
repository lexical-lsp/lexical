defmodule Lexical.SourceFile do
  @moduledoc """
  A representation of a LSP text document

  A source file is the fundamental data structure of the Lexical language server.
  All language server documents are represented and backed by source files, which
  provide functionality for fetching lines, applying changes, and tracking versions.
  """
  alias Lexical.Convertible
  alias Lexical.SourceFile.Document
  alias Lexical.SourceFile.Edit
  alias Lexical.SourceFile.Line
  alias Lexical.SourceFile.Position
  alias Lexical.SourceFile.Range

  import Lexical.SourceFile.Line

  alias __MODULE__.Path, as: SourceFilePath

  @derive {Inspect, only: [:path, :version, :dirty?, :document]}

  defstruct [:uri, :path, :version, dirty?: false, document: nil]

  @type version :: non_neg_integer()
  @type t :: %__MODULE__{
          uri: String.t(),
          version: version(),
          dirty?: boolean,
          document: Document.t(),
          path: String.t()
        }

  @type change_application_error :: {:error, {:invalid_range, map()}}

  # public

  @doc """
  Creates a new source fie from a uri or path, the source code
  as a binary and the vewrsion.
  """
  @spec new(Lexical.path() | Lexical.uri(), String.t(), version()) :: t
  def new(maybe_uri, text, version) do
    uri = SourceFilePath.ensure_uri(maybe_uri)

    %__MODULE__{
      uri: uri,
      version: version,
      document: Document.new(text),
      path: SourceFilePath.from_uri(uri)
    }
  end

  @doc """
  Returns the number of lines in the document
  """
  @spec size(t) :: non_neg_integer()
  def size(%__MODULE__{} = source) do
    Document.size(source.document)
  end

  @doc """
  Marks the source file as dirty
  """
  @spec mark_dirty(t) :: t
  def mark_dirty(%__MODULE__{} = source) do
    %__MODULE__{source | dirty?: true}
  end

  @doc """
  Marks the source file as clean
  """

  @spec mark_clean(t) :: t
  def mark_clean(%__MODULE__{} = source) do
    %__MODULE__{source | dirty?: false}
  end

  @doc """
  Fetches the text at the given line

  Returns {:ok, text} if the line exists, and :error if it doesn't
  """
  @spec fetch_text_at(t, version()) :: {:ok, String.t()} | :error
  def fetch_text_at(%__MODULE__{} = source, line_number) do
    case fetch_line_at(source, line_number) do
      {:ok, line(text: text)} -> {:ok, text}
      _ -> :error
    end
  end

  @spec fetch_line_at(t, version()) :: {:ok, Line.t()} | :error
  def fetch_line_at(%__MODULE__{} = source, line_number) do
    case Document.fetch_line(source.document, line_number) do
      {:ok, line} -> {:ok, line}
      _ -> :error
    end
  end

  @spec apply_content_changes(t, version(), [Convertible.t() | nil]) ::
          {:ok, t} | change_application_error()
  def apply_content_changes(%__MODULE__{version: current_version}, new_version, _)
      when new_version <= current_version do
    {:error, :invalid_version}
  end

  def apply_content_changes(%__MODULE__{} = source, _, []) do
    {:ok, source}
  end

  def apply_content_changes(%__MODULE__{} = source, version, changes) when is_list(changes) do
    result =
      Enum.reduce_while(changes, source, fn
        nil, source ->
          {:cont, source}

        change, source ->
          case apply_change(source, change) do
            {:ok, new_source} ->
              {:cont, new_source}

            error ->
              {:halt, error}
          end
      end)

    case result do
      %__MODULE__{} = source ->
        source = mark_dirty(%__MODULE__{source | version: version})

        {:ok, source}

      error ->
        error
    end
  end

  def to_string(%__MODULE__{} = source) do
    source
    |> to_iodata()
    |> IO.iodata_to_binary()
  end

  # private

  defp line_count(%__MODULE__{} = source) do
    Document.size(source.document)
  end

  defp apply_change(
         %__MODULE__{} = source,
         %Range{start: %Position{} = start_pos, end: %Position{} = end_pos},
         new_text
       ) do
    start_line = start_pos.line

    new_lines_iodata =
      cond do
        start_line > line_count(source) ->
          append_to_end(source, new_text)

        start_line < 1 ->
          prepend_to_beginning(source, new_text)

        true ->
          apply_valid_edits(source, new_text, start_pos, end_pos)
      end

    new_document =
      new_lines_iodata
      |> IO.iodata_to_binary()
      |> Document.new()

    {:ok, %__MODULE__{source | document: new_document}}
  end

  defp apply_change(%__MODULE__{} = source, %Edit{range: nil} = edit) do
    {:ok, %__MODULE__{source | document: Document.new(edit.text)}}
  end

  defp apply_change(%__MODULE__{} = source, %Edit{range: %Range{}} = edit) do
    if valid_edit?(edit) do
      apply_change(source, edit.range, edit.text)
    else
      {:error, {:invalid_range, edit.range}}
    end
  end

  defp apply_change(%__MODULE__{} = source, %{range: range, text: text}) do
    with {:ok, native_range} <- Convertible.to_native(range, source) do
      apply_change(source, Edit.new(text, native_range))
    end
  end

  defp apply_change(%__MODULE__{} = source, convertable_edit) do
    with {:ok, edit} <- Convertible.to_native(convertable_edit, source) do
      apply_change(source, edit)
    end
  end

  defp valid_edit?(%Edit{
         range: %Range{start: %Position{} = start_pos, end: %Position{} = end_pos}
       }) do
    start_pos.line >= 0 and start_pos.character >= 0 and end_pos.line >= 0 and
      end_pos.character >= 0
  end

  defp append_to_end(%__MODULE__{} = source, edit_text) do
    [to_iodata(source), edit_text]
  end

  defp prepend_to_beginning(%__MODULE__{} = source, edit_text) do
    [edit_text, to_iodata(source)]
  end

  defp apply_valid_edits(%__MODULE__{} = source, edit_text, start_pos, end_pos) do
    Document.reduce(source.document, [], fn line() = line, acc ->
      case edit_action(line, edit_text, start_pos, end_pos) do
        :drop ->
          acc

        {:append, io_data} ->
          [acc, io_data]
      end
    end)
  end

  defp edit_action(line() = line, edit_text, %Position{} = start_pos, %Position{} = end_pos) do
    %Position{line: start_line, character: start_char} = start_pos
    %Position{line: end_line, character: end_char} = end_pos

    line(line_number: line_number, text: text, ending: ending) = line

    cond do
      line_number < start_line ->
        {:append, [text, ending]}

      line_number > end_line ->
        {:append, [text, ending]}

      line_number == start_line && line_number == end_line ->
        prefix_text = utf8_prefix(line, start_char)
        suffix_text = utf8_suffix(line, end_char)
        {:append, [prefix_text, edit_text, suffix_text, ending]}

      line_number == start_line ->
        prefix_text = utf8_prefix(line, start_char)
        {:append, [prefix_text, edit_text]}

      line_number == end_line ->
        suffix_text = utf8_suffix(line, end_char)
        {:append, [suffix_text, ending]}

      true ->
        :drop
    end
  end

  defp utf8_prefix(line(text: text), start_code_unit) do
    length = max(0, start_code_unit - 1)
    binary_part(text, 0, length)
  end

  defp utf8_suffix(line(text: text), start_code_unit) do
    byte_count = byte_size(text)
    start_index = min(start_code_unit - 1, byte_count)
    length = byte_count - start_index

    binary_part(text, start_index, length)
  end

  defp to_iodata(%__MODULE__{} = source) do
    Document.to_iodata(source.document)
  end

  # defp increment_version(%__MODULE__{} = source) do
  #   %__MODULE__{source | version: source.version + 1}
  # end
end
