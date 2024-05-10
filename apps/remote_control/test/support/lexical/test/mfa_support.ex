defmodule Lexical.Test.MfaSupport do
  defmacro mfa(ast) do
    {m, f, a} = Macro.decompose_call(ast)

    quote do
      {:mfa, unquote(m), unquote(f), unquote(a)}
    end
  end
end
