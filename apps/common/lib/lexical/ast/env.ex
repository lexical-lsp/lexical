defmodule Lexical.Ast.Env do
  @moduledoc """
  Representation of the environment at a given position in a document.

  This module implements the `Lexical.Ast.Environment` behaviour.
  """

  alias Lexical.Ast
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Detection
  alias Lexical.Ast.Environment
  alias Lexical.Ast.Tokens
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Project

  defstruct [
    :project,
    :analysis,
    :document,
    :line,
    :prefix,
    :suffix,
    :position,
    :zero_based_character
  ]

  @type t :: %__MODULE__{
          project: Project.t(),
          analysis: Analysis.t(),
          prefix: String.t(),
          suffix: String.t(),
          position: Position.t(),
          zero_based_character: non_neg_integer()
        }

  @behaviour Environment
  def new(%Project{} = project, %Analysis{} = analysis, %Position{} = cursor_position) do
    zero_based_character = cursor_position.character - 1

    case Document.fetch_text_at(analysis.document, cursor_position.line) do
      {:ok, line} ->
        prefix = String.slice(line, 0, zero_based_character)
        suffix = String.slice(line, zero_based_character..-1)

        env = %__MODULE__{
          analysis: Ast.reanalyze_to(analysis, cursor_position),
          document: analysis.document,
          line: line,
          position: cursor_position,
          prefix: prefix,
          project: project,
          suffix: suffix,
          zero_based_character: zero_based_character
        }

        {:ok, env}

      _ ->
        {:error, {:out_of_bounds, cursor_position}}
    end
  end

  @impl Environment
  def prefix_tokens(%__MODULE__{} = env, count \\ :all) do
    stream = Tokens.prefix_stream(env.document, env.position)

    case count do
      :all ->
        stream

      count when is_integer(count) ->
        Enum.take(stream, count)
    end
  end

  @impl Environment
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def in_context?(%__MODULE__{} = env, context_type) do
    document = env.document
    position = env.position

    case context_type do
      :alias ->
        Detection.Alias.detected?(document, position)

      :bitstring ->
        Detection.Bitstring.detected?(document, position)

      :function_capture ->
        Detection.FunctionCapture.detected?(document, position)

      :import ->
        Detection.Import.detected?(document, position)

      :pipe ->
        Detection.Pipe.detected?(document, position)

      :require ->
        Detection.Require.detected?(document, position)

      :spec ->
        Detection.Spec.detected?(document, position)

      :struct_fields ->
        Detection.StructFields.detected?(document, position)

      :struct_field_key ->
        Detection.StructFieldKey.detected?(document, position)

      :struct_field_value ->
        Detection.StructFieldValue.detected?(document, position)

      :struct_reference ->
        Detection.StructReference.detected?(document, position)

      :type ->
        Detection.Type.detected?(document, position)

      :use ->
        Detection.Use.detected?(document, position)
    end
  end

  @impl Environment
  def empty?("") do
    true
  end

  @impl Environment
  def empty?(string) when is_binary(string) do
    String.trim(string) == ""
  end
end
