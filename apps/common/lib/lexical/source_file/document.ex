defmodule Lexical.SourceFile.Document do
  @moduledoc """
  A hyper-optimized, line-based backing store for text documents
  """
  alias Lexical.SourceFile.Line
  alias Lexical.SourceFile.LineParser

  use Lexical.StructAccess
  import Line

  @default_starting_index 1

  defstruct lines: nil, starting_index: @default_starting_index

  @type t :: %__MODULE__{}

  def new(text, starting_index \\ @default_starting_index) do
    lines =
      text
      |> LineParser.parse(starting_index)
      |> List.to_tuple()

    %__MODULE__{lines: lines, starting_index: starting_index}
  end

  def to_iodata(%__MODULE__{} = document) do
    reduce(document, [], fn line(text: text, ending: ending), acc ->
      [acc | [text | ending]]
    end)
  end

  def to_string(%__MODULE__{} = document) do
    document
    |> to_iodata()
    |> IO.iodata_to_binary()
  end

  def size(%__MODULE__{} = document) do
    tuple_size(document.lines)
  end

  def fetch_line(%__MODULE__{lines: lines, starting_index: starting_index}, index)
      when index - starting_index >= tuple_size(lines) do
    :error
  end

  def fetch_line(%__MODULE__{lines: {}}, _) do
    :error
  end

  def fetch_line(%__MODULE__{} = document, index) when is_integer(index) do
    case elem(document.lines, index - document.starting_index) do
      line() = line -> {:ok, line}
      _ -> :error
    end
  end

  def reduce(%__MODULE__{} = document, initial, reducer_fn) do
    size = size(document)

    if size == 0 do
      initial
    else
      Enum.reduce(0..(size - 1), initial, fn index, acc ->
        document.lines
        |> elem(index)
        |> reducer_fn.(acc)
      end)
    end
  end
end

defimpl Inspect, for: Lexical.SourceFile.Document do
  alias Lexical.SourceFile.Document
  alias Lexical.SourceFile.Line

  import Inspect.Algebra
  import Line

  def inspect(%Document{lines: {}}) do
    concat([empty(), "%Document<empty>"])
  end

  def inspect(document, opts) do
    document_body =
      case Document.fetch_line(document, 1) do
        {:ok, line(text: text)} ->
          concat(empty(), to_doc(text <> "...", opts))

        :error ->
          " empty "
      end

    line_or_lines =
      if Document.size(document) == 1 do
        "line"
      else
        "lines"
      end

    concat([
      empty(),
      "%Document<",
      document_body,
      "(",
      space(
        to_doc(Document.size(document), opts),
        line_or_lines
      ),
      ")>"
    ])
  end
end

defimpl Enumerable, for: Lexical.SourceFile.Document do
  alias Lexical.SourceFile.Document

  def count(%Document{} = document) do
    {:ok, Document.size(document)}
  end

  def member?(%Document{}, _) do
    {:error, Document}
  end

  def reduce(%Document{} = document, acc, fun) do
    tuple_reduce({0, tuple_size(document.lines), document.lines}, acc, fun)
  end

  def slice(%Document{} = document) do
    {:ok, Document.size(document), fn start, len -> do_slice(document, start, len) end}
  end

  defp do_slice(%Document{} = document, start, 1) do
    [elem(document.lines, start)]
  end

  defp do_slice(%Document{} = document, start, length) do
    Enum.map(start..(start + length - 1), &elem(document.lines, &1))
  end

  defp tuple_reduce(_, {:halt, acc}, _fun) do
    {:halted, acc}
  end

  defp tuple_reduce(current_state, {:suspend, acc}, fun) do
    {:suspended, acc, &tuple_reduce(current_state, &1, fun)}
  end

  defp tuple_reduce({same, same, _}, {:cont, acc}, _) do
    {:done, acc}
  end

  defp tuple_reduce({index, size, tuple}, {:cont, acc}, fun) do
    tuple_reduce({index + 1, size, tuple}, fun.(elem(tuple, index), acc), fun)
  end
end
