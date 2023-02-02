# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.ErrorCodes do
  alias Lexical.Protocol.Proto
  use Proto

  defenum parse_error: -32_700,
          invalid_request: -32_600,
          method_not_found: -32_601,
          invalid_params: -32_602,
          internal_error: -32_603,
          server_not_initialized: -32_002,
          unknown_error_code: -32_001
end
