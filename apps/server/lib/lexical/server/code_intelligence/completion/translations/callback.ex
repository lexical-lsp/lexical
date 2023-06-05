defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Callback do
  alias Lexical.RemoteControl.Completion.Result
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translatable
  alias Lexical.Server.CodeIntelligence.Completion.Translations.Callable

  use Translatable.Impl, for: Result.Callback

  def translate(%Result.Callback{} = callback, _builder, %Env{} = env) do
    Callable.completion(callback, env)
  end
end
