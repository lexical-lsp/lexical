defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Callback do
  alias Lexical.Ast.Env
  alias Lexical.Completion.Translatable
  alias Lexical.RemoteControl.Completion.Candidate
  alias Lexical.Server.CodeIntelligence.Completion.Translations

  defimpl Translatable, for: Candidate.Callback do
    def translate(callback, _builder, %Env{} = env) do
      Translations.Callable.completion(callback, env)
    end
  end
end
