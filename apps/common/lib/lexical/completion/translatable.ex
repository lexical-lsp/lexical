defprotocol Lexical.Completion.Translatable do
  alias Lexical.Ast.Environment
  alias Lexical.Completion.Builder

  @type t :: any()

  @fallback_to_any true
  @spec translate(t(), Builder.t(), Environment.t()) :: Builder.result()
  def translate(item, builder, env)
end

defimpl Lexical.Completion.Translatable, for: Any do
  def translate(_any, _builder, _environment) do
    :skip
  end
end
