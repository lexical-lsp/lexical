defmodule Lexical.RemoteControl.Api.Proxy.Records do
  import Record

  defrecord :message, body: nil
  defrecord :mfa, module: nil, function: nil, arguments: []

  def mfa(module, function, arguments) do
    mfa(module: module, function: function, arguments: arguments)
  end

  defmacro to_mfa(ast) do
    {m, f, a} = Macro.decompose_call(ast)

    quote do
      require unquote(__MODULE__)
      mfa(module: unquote(m), function: unquote(f), arguments: unquote(a))
    end
  end
end
