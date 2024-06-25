defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Typespec do
  alias Lexical.Ast.Env
  alias Lexical.RemoteControl.Completion.Candidate
  alias Lexical.Server.CodeIntelligence.Completion.Translatable
  alias Lexical.Server.CodeIntelligence.Completion.Translations.Callable

  defimpl Translatable, for: Candidate.Typespec do
    def translate(typespec, _builder, %Env{} = env) do
      Callable.completion(typespec, env)
    end
  end
end
