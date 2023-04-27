defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Variable do
  alias Lexical.RemoteControl.Completion.Result
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translatable

  use Translatable.Impl, for: Result.Variable

  def translate(%Result.Variable{} = variable, builder, %Env{} = env) do
    builder.plain_text(env, variable.name,
      detail: variable.name,
      kind: :variable,
      label: variable.name
    )
  end
end
