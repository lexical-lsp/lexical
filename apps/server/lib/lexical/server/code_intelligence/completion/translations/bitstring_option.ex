defmodule Lexical.Server.CodeIntelligence.Completion.Translations.BitstringOption do
  alias Lexical.RemoteControl.Completion.Candidate
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translatable

  use Translatable.Impl, for: Candidate.BitstringOption
  require Logger

  def translate(%Candidate.BitstringOption{} = option, builder, %Env{} = env) do
    start_character = env.position.character - prefix_length(env)

    env
    |> builder.text_edit(option.name, {start_character, env.position.character},
      filter_text: option.name,
      kind: :unit,
      label: option.name
    )
    |> builder.boost(5)
  end

  defp prefix_length(%Env{} = env) do
    case Env.prefix_tokens(env, 1) do
      [{:operator, :"::"}] ->
        0

      [{:operator, :in}] ->
        # they're typing integer and got "in" out, which the lexer thinks
        # is Kernel.in/2
        2

      [{_, token}] when is_binary(token) ->
        String.length(token)

      [{_, token}] when is_list(token) ->
        length(token)

      [{_, token}] when is_atom(token) ->
        token |> Atom.to_string() |> String.length()
    end
  end
end
