import Config
alias Lexical.Server.JsonRpc

Logger.remove_backend(:console)
Logger.remove_backend(JsonRpc.Backend)
config :logger, level: :error, backends: []
