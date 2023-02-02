# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.ShowMessageRequest.ClientCapabilities do
  alias Lexical.Protocol.Proto
  alias __MODULE__, as: Parent

  defmodule MessageActionItem do
    use Proto
    deftype additional_properties_support: optional(boolean())
  end

  use Proto
  deftype message_action_item: optional(Parent.MessageActionItem)
end
