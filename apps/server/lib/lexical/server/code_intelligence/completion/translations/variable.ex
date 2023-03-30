defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Variable do
  alias Lexical.RemoteControl.Completion.Result
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translator

  use Translator, for: Result.Variable

  def translate(%Result.Variable{} = variable, %Env{}) do
    plain_text(variable.name,
      detail: variable.name,
      kind: :variable,
      label: variable.name
    )
  end
end
