defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Function do
  alias Lexical.Ast.Env
  alias Lexical.RemoteControl.Completion.Candidate
  alias Lexical.Server.CodeIntelligence.Completion.Translatable
  alias Lexical.Server.CodeIntelligence.Completion.Translations

  defimpl Translatable, for: Candidate.Function do
    def translate(function, _builder, %Env{} = env) do
      if Env.in_context?(env, :function_capture) do
        Translations.Callable.capture_completions(function, env)
      else
        Translations.Callable.completion(function, env)
      end
    end
  end
end
