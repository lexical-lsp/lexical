# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.SignatureHelp.ClientCapabilities do
  alias Lexical.Proto
  alias Lexical.Protocol.Types
  alias __MODULE__, as: Parent

  defmodule ParameterInformation do
    use Proto
    deftype label_offset_support: optional(boolean())
  end

  defmodule SignatureInformation do
    use Proto

    deftype active_parameter_support: optional(boolean()),
            documentation_format: optional(list_of(Types.Markup.Kind)),
            parameter_information: optional(Parent.ParameterInformation)
  end

  use Proto

  deftype context_support: optional(boolean()),
          dynamic_registration: optional(boolean()),
          signature_information: optional(Parent.SignatureInformation)
end
