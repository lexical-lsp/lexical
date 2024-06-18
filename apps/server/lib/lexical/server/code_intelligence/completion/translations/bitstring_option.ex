defmodule Lexical.Server.CodeIntelligence.Completion.Translations.BitstringOption do
  alias Lexical.Ast.Env
  alias Lexical.RemoteControl.Completion.Candidate
  alias Lexical.Server.CodeIntelligence.Completion.SortScope
  alias Lexical.Server.CodeIntelligence.Completion.Translatable
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
