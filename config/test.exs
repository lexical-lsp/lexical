import Config
alias Lexical.Server.JsonRpc
alias Lexical.Test.Transport.NoOp

config :logger, level: :none
config :remote_control, edit_window_millis: 10
config :server, transport: NoOp

if Version.match?(System.version(), ">= 1.15.0") do
  Logger.configure(level: :none)
else
  Logger.remove_backend(:console)
  Logger.remove_backend(JsonRpc.Backend)
end
