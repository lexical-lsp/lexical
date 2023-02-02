# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.Initialize.Result do
  alias Lexical.Protocol.Proto
  alias Lexical.Protocol.Types
  alias __MODULE__, as: Parent

  defmodule ServerInfo do
    use Proto
    deftype name: string(), version: optional(string())
  end

  use Proto
  deftype capabilities: Types.ServerCapabilities, server_info: optional(Parent.ServerInfo)
end
