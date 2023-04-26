defmodule Lexical.Proto.LspTypes do
  alias Lexical.Proto
  use Proto

  defmodule ErrorCodes do
    use Proto

    defenum parse_error: -32_700,
            invalid_request: -32_600,
            method_not_found: -32_601,
            invalid_params: -32_602,
            internal_error: -32_603,
            server_not_initialized: -32_002,
            unknown_error_code: -32_001,
            request_failed: -32_803,
            server_cancelled: -32_802,
            content_modified: -32_801,
            request_cancelled: -32_800
  end

  defmodule ResponseError do
    use Proto
    deftype code: ErrorCodes, message: string(), data: optional(any())
  end

  defmodule ClientInfo do
    use Proto
    deftype name: string(), version: optional(string())
  end

  defmodule TraceValue do
    use Proto
    defenum off: "off", messages: "messages", verbose: "verbose"
  end

  defmodule Registration do
    use Proto

    deftype id: string(), method: string(), register_options: optional(any())
  end
end
