defmodule Lexical.Server.CodeIntelligence.Completion.Translations.BitstringOption do
  alias Lexical.Ast.Env
  alias Lexical.Completion.SortScope
  alias Lexical.Completion.Translatable
  alias Lexical.RemoteControl.Completion.Candidate
  alias Lexical.Server.CodeIntelligence.Completion.Translations

  require Logger

  defimpl Translatable, for: Candidate.BitstringOption do
    def translate(option, builder, %Env{} = env) do
      Translations.BitstringOption.translate(option, builder, env)
    end
  end

  def translate(%Candidate.BitstringOption{} = option, builder, %Env{} = env) do
    env
    |> builder.plain_text(option.name,
      filter_text: option.name,
      kind: :unit,
      label: option.name
    )
    |> builder.set_sort_scope(SortScope.global())
  end
end
