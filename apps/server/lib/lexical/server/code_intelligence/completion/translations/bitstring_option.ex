defmodule Lexical.Server.CodeIntelligence.Completion.Translations.BitstringOption do
  alias Lexical.RemoteControl.Completion.Result
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translatable

  use Translatable.Impl, for: Result.BitstringOption
  require Logger

  def translate(%Result.BitstringOption{} = option, builder, %Env{} = env) do
    context = match_context(env)
    insert_text = context <> option.name

    builder.plain_text(env, insert_text,
      label: option.name,
      kind: :unit,
      sort_text: builder.boost(option.name, 10)
    )
  end

  defp match_context(%Env{} = env) do
    case Env.prefix_tokens(env) do
      [{_, :"::"} | rest] ->
        rebuild_context(rest) <> "::"

      [_ | rest] ->
        rebuild_context(rest)
    end
  end

  defp rebuild_context(orig_context) do
    rebuild_context(orig_context, [])
  end

  defp rebuild_context([], acc) do
    IO.iodata_to_binary(acc)
  end

  defp rebuild_context([{:comma, _} | _], acc) do
    IO.iodata_to_binary(acc)
  end

  defp rebuild_context([{:operator, :-} | _], acc) do
    IO.iodata_to_binary(acc)
  end

  defp rebuild_context([{:operator, :"<<"} | _], acc) do
    IO.iodata_to_binary(acc)
  end

  defp rebuild_context([{_type, val} | rest], acc) do
    rebuild_context(rest, [to_string(val), acc])
  end
end
