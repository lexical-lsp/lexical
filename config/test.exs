import Config
alias Lexical.Server.JsonRpc
alias Lexical.Test.Transport.NoOp

Logger.remove_backend(:console)
Logger.remove_backend(JsonRpc.Backend)
config :logger, level: :error, backends: []

config :remote_control, edit_window_millis: 10

config :server, transport: NoOp
