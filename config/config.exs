import Config
alias Lexical.Server.JsonRpc.Backend, as: JsonRpcBackend

cond do
  Code.ensure_loaded?(LoggerFileBackend) ->
    config :logger,
      backends: [{LoggerFileBackend, :general_log}]

    config :logger, :general_log,
      path: "/Users/steve/Projects/lexical/lsp.log",
      handle_sasl_reports: true,
      handle_otp_reports: true,
      level: :debug

  Code.ensure_loaded?(JsonRpcBackend) ->
    config :logger,
      backends: [JsonRpcBackend]

    config :logger, JsonRpcBackend,
      level: :debug,
      format: "$message",
      metadata: []

  true ->
    :ok
end

import_config("#{Mix.env()}.exs")
