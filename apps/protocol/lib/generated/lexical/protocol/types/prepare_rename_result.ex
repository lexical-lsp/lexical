# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.PrepareRenameResult do
  alias Lexical.Proto
  alias Lexical.Protocol.Types

  defmodule PrepareRenameResult do
    use Proto
    deftype placeholder: string(), range: Types.Range
  end

  defmodule PrepareRenameResult1 do
    use Proto
    deftype default_behavior: boolean()
  end

  use Proto

  defalias one_of([
             Types.Range,
             Lexical.Protocol.Types.PrepareRenameResult.PrepareRenameResult,
             Lexical.Protocol.Types.PrepareRenameResult.PrepareRenameResult1
           ])
end
