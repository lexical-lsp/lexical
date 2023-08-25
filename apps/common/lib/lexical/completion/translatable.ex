defprotocol Lexical.Completion.Translatable do
  alias Lexical.Ast.Environment
  alias Lexical.Completion.Builder

  @type t :: any()

  @fallback_to_any true
  @spec translate(t(), Builder.t(), Environment.t()) :: Builder.result()
  def translate(item, builder, env)
end

defimpl Lexical.Completion.Translatable, for: Any do
  defmacro __deriving__(module, _struct, caller_module) do
    quote do
      unquote(protocol_implementation(caller_module, module))
    end
  end

  def translate(_any, _builder, _environment) do
    :skip
  end

  defp protocol_implementation(caller_module, translated_module) do
    quote do
      defimpl Lexical.Completion.Translatable, for: unquote(translated_module) do
        def translate(item, builder, env) do
          unquote(caller_module).translate(item, builder, env)
        end
      end
    end
  end
end
