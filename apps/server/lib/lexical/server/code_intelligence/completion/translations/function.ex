defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Function do
  alias Lexical.RemoteControl.Completion.Result
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translatable
  alias Lexical.Server.CodeIntelligence.Completion.Translations.Callable

  use Translatable.Impl, for: Result.Function

  def translate(%Result.Function{} = function, _builder, %Env{} = env) do
    if Env.function_capture?(env) do
      Callable.capture_completions(function, env)
    else
      Callable.completion(function, env)
    end
  end
end
