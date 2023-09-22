defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Variable do
  alias Lexical.Ast.Env
  alias Lexical.Completion.Translatable
  alias Lexical.RemoteControl.Completion.Candidate

  defimpl Translatable, for: Candidate.Variable do
    def translate(variable, builder, %Env{} = env) do
      builder.plain_text(env, variable.name,
        detail: variable.name,
        kind: :variable,
        label: variable.name
      )
    end
  end
end
