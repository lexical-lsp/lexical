defmodule Lexical.Server.CodeIntelligence.Completion.Translatable.Impl do
  alias Lexical.Completion.Translatable
  require Protocol

  defmacro __using__(for: what_to_translate) do
    caller_module = __CALLER__.module

    what_to_translate
    |> List.wrap()
    |> Enum.map(&Protocol.derive(Translatable, Macro.expand(&1, __CALLER__), caller_module))
  end
end
