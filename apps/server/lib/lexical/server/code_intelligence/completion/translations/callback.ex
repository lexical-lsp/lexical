defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Callback do
  alias Lexical.RemoteControl.Completion.Candidate
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translatable
  alias Lexical.Server.CodeIntelligence.Completion.Translations.Callable

  use Translatable.Impl, for: Candidate.Callback

  def translate(%Candidate.Callback{} = callback, _builder, %Env{} = env) do
    Callable.completion(callback, env)
  end
end
