defmodule Lexical.RemoteControl.Api.Proxy.Records do
  alias Lexical.Formats

  import Record

  defrecord :message, body: nil
  defrecord :mfa, module: nil, function: nil, arguments: []

  def mfa(module, function, arguments) do
    mfa(module: module, function: function, arguments: arguments)
  end

  defmacro to_mfa(ast) do
    {m, f, a} = Macro.decompose_call(ast)
    module = Macro.expand(m, __CALLER__)
    arity = length(a)

    Code.ensure_loaded!(module)

    unless function_exported?(module, f, arity) do
      mfa = Formats.mfa(module, f, arity)

      raise CompileError.message(%{
              file: __CALLER__.file,
              line: __CALLER__.line,
              description: "No function named #{mfa} defined. Proxy will fail"
            })
    end

    quote do
      require unquote(__MODULE__)
      mfa(module: unquote(m), function: unquote(f), arguments: unquote(a))
    end
  end
end
