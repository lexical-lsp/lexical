defmodule Lexical.Ast.Env do
  @moduledoc """
  Representation of the environment at a given position in a document.

  This module implements the `Lexical.Ast.Environment` behaviour.
  """

  alias Lexical.Ast
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Analysis.Scope
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
    :position_module,
    :zero_based_character
  ]

  @type t :: %__MODULE__{
          project: Project.t(),
          analysis: Analysis.t(),
          prefix: String.t(),
          suffix: String.t(),
          position: Position.t(),
          position_module: String.t(),
          zero_based_character: non_neg_integer()
        }

  @behaviour Environment
  def new(%Project{} = project, %Analysis{} = analysis, %Position{} = cursor_position) do
    zero_based_character = cursor_position.character - 1

    case Document.fetch_text_at(analysis.document, cursor_position.line) do
      {:ok, line} ->
        prefix = String.slice(line, 0, zero_based_character)
        suffix = String.slice(line, zero_based_character..-1//1)

        analysis = Ast.reanalyze_to(analysis, cursor_position)

        cursor_module =
          case Analysis.scopes_at(analysis, cursor_position) do
            [%Scope{module: local_module} | _] ->
              Enum.join(local_module, ".")

            [] ->
              ""
          end

        env = %__MODULE__{
          analysis: analysis,
          document: analysis.document,
          line: line,
          position: cursor_position,
          position_module: cursor_module,
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
    analysis = env.analysis
    position = env.position

    case context_type do
      :alias ->
        Detection.Alias.detected?(analysis, position)

      :behaviour ->
        Detection.ModuleAttribute.detected?(analysis, position, :behaviour)

      :bitstring ->
        Detection.Bitstring.detected?(analysis, position)

      :comment ->
        Detection.Comment.detected?(analysis, position)

      :doc ->
        Detection.ModuleAttribute.detected?(analysis, position, :doc)

      :function_capture ->
        Detection.FunctionCapture.detected?(analysis, position)

      :impl ->
        Detection.ModuleAttribute.detected?(analysis, position, :impl)

      :import ->
        Detection.Import.detected?(analysis, position)

      :module_attribute ->
        Detection.ModuleAttribute.detected?(analysis, position)

      {:module_attribute, name} ->
        Detection.ModuleAttribute.detected?(analysis, position, name)

      :moduledoc ->
        Detection.ModuleAttribute.detected?(analysis, position, :moduledoc)

      :pipe ->
        Detection.Pipe.detected?(analysis, position)

      :require ->
        Detection.Require.detected?(analysis, position)

      :spec ->
        Detection.Spec.detected?(analysis, position)

      :struct_fields ->
        Detection.StructFields.detected?(analysis, position)

      :struct_field_key ->
        Detection.StructFieldKey.detected?(analysis, position)

      :struct_field_value ->
        Detection.StructFieldValue.detected?(analysis, position)

      :struct_reference ->
        Detection.StructReference.detected?(analysis, position)

      :type ->
        Detection.Type.detected?(analysis, position)

      :use ->
        Detection.Use.detected?(analysis, position)
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
