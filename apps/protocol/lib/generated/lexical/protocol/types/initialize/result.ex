# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.Initialize.Result do
  alias Lexical.Proto
  alias Lexical.Protocol.Types

  defmodule ServerInfo do
    use Proto
    deftype name: string(), version: optional(string())
  end

  use Proto

  deftype capabilities: Types.ServerCapabilities,
          server_info: optional(Lexical.Protocol.Types.Initialize.Result.ServerInfo)
end
