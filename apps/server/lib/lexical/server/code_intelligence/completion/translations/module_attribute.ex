defmodule Lexical.Server.CodeIntelligence.Completion.Translations.ModuleAttribute do
  alias Lexical.Ast.Env
  alias Lexical.RemoteControl.Completion.Candidate
  alias Lexical.Server.CodeIntelligence.Completion.Translatable
  alias Lexical.Server.CodeIntelligence.Completion.Translations

  defimpl Translatable, for: Candidate.ModuleAttribute do
    def translate(attribute, builder, %Env{} = env) do
      Translations.ModuleAttribute.translate(attribute, builder, env)
    end
  end

  def translate(%Candidate.ModuleAttribute{name: "@moduledoc"}, builder, env) do
    doc_snippet = ~s'''
    @moduledoc """
    $0
    """
    '''

    case fetch_range(env) do
      {:ok, range} ->
        with_doc =
          builder.text_edit_snippet(env, doc_snippet, range,
            detail: "Document public module",
            kind: :property,
            label: "@moduledoc"
          )

        without_doc =
          builder.text_edit(env, "@moduledoc false", range,
            detail: "Mark as private",
            kind: :property,
            label: "@moduledoc false"
          )

        [with_doc, without_doc]

      :error ->
        :skip
    end
  end

  def translate(%Candidate.ModuleAttribute{name: "@doc"}, builder, env) do
    doc_snippet = ~s'''
    @doc """
    $0
    """
    '''

    case fetch_range(env) do
      {:ok, range} ->
        with_doc =
          builder.text_edit_snippet(env, doc_snippet, range,
            detail: "Document public function",
            kind: :property,
            label: "@doc"
          )

        without_doc =
          builder.text_edit(env, "@doc false", range,
            detail: "Mark as private",
            kind: :property,
            label: "@doc false"
          )

        [with_doc, without_doc]

      :error ->
        :skip
    end
  end

  def translate(%Candidate.ModuleAttribute{} = attribute, builder, env) do
    case fetch_range(env) do
      {:ok, range} ->
        builder.text_edit(env, attribute.name, range,
          detail: "module attribute",
          kind: :constant,
          label: attribute.name
        )

      :error ->
        :skip
    end
  end

  defp fetch_range(%Env{} = env) do
    case fetch_at_op_on_same_line(env) do
      {:ok, {:at_op, _, {_line, char}}} ->
        {:ok, {char, env.position.character}}

      _ ->
        :error
    end
  end

  defp fetch_at_op_on_same_line(%Env{} = env) do
    Enum.reduce_while(Env.prefix_tokens(env), :error, fn
      {:at_op, _, _} = at_op, _acc ->
        {:halt, {:ok, at_op}}

      {:eol, _, _}, _acc ->
        {:halt, :error}

      _, acc ->
        {:cont, acc}
    end)
  end
end
