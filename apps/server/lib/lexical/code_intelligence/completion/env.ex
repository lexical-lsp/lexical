defmodule Lexical.CodeIntelligence.Completion.Env do
  alias Lexical.Protocol.Types.Completion
  alias Lexical.SourceFile.Position
  alias Lexical.SourceFile
  defstruct [:document, :context, :prefix, :suffix, :position, :words]

  def new(
        %SourceFile{} = document,
        %Position{} = cursor_position,
        %Completion.Context{} = context
      ) do
    with {:ok, line} <- SourceFile.fetch_text_at(document, cursor_position.line) do
      graphemes = String.graphemes(line)
      prefix = graphemes |> Enum.take(cursor_position.character) |> IO.iodata_to_binary()
      suffix = String.slice(line, cursor_position.character..-1)
      words = String.split(prefix)

      {:ok,
       %__MODULE__{
         document: document,
         prefix: prefix,
         suffix: suffix,
         position: cursor_position,
         words: words,
         context: context
       }}
    else
      _ ->
        {:error, :out_of_bounds}
    end
  end

  def empty?("") do
    true
  end

  def empty?(string) when is_binary(string) do
    String.trim(string) == ""
  end

  def last_word(%__MODULE__{} = env) do
    List.last(env.words)
  end
end
