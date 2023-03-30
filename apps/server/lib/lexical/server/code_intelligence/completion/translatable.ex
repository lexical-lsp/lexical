defprotocol Lexical.Completion.Translatable do
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Protocol.Types.Completion.Item

  @fallback_to_any true
  @spec translate(any, Env.t()) :: [Item.t()] | :skip
  def translate(item, env)
end

defimpl Lexical.Completion.Translatable, for: Any do
  def translate(_, _) do
    :skip
  end
end
