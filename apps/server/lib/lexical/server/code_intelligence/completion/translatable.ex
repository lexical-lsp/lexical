defprotocol Lexical.Server.CodeIntelligence.Completion.Translatable do
  alias Lexical.Ast.Env
  alias Lexical.Protocol.Types.Completion
  alias Lexical.Server.CodeIntelligence.Completion.Builder

  @type t :: any()

  @type translated :: [Completion.Item.t()] | Completion.Item.t() | :skip

  @fallback_to_any true
  @spec translate(t, Builder.t(), Env.t()) :: translated
  def translate(item, builder, env)
end

defimpl Lexical.Server.CodeIntelligence.Completion.Translatable, for: Any do
  def translate(_any, _builder, _environment) do
    :skip
  end
end
