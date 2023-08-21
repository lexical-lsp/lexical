defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Variable do
  alias Lexical.Ast.Env
  alias Lexical.RemoteControl.Completion.Candidate
  alias Lexical.Server.CodeIntelligence.Completion.Translatable

  use Translatable.Impl, for: Candidate.Variable

  def translate(%Candidate.Variable{} = variable, builder, %Env{} = env) do
    builder.plain_text(env, variable.name,
      detail: variable.name,
      kind: :variable,
      label: variable.name
    )
  end
end
