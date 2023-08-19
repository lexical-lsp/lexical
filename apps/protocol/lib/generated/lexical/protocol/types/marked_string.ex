# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.MarkedString do
  alias Lexical.Proto

  defmodule MarkedString do
    use Proto
    deftype language: string(), value: string()
  end

  use Proto
  defalias one_of([string(), Lexical.Protocol.Types.MarkedString.MarkedString])
end
