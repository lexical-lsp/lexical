import Config
alias Lexical.Server.JsonRpc
alias Lexical.Test.Transport.NoOp

config :logger, level: :none

config :remote_control,
  edit_window_millis: 10,
  modules_cache_expiry: {50, :millisecond}

config :server, transport: NoOp
config :stream_data, initial_size: 50

if Version.match?(System.version(), ">= 1.15.0") do
  Logger.configure(level: :none)
else
  Logger.remove_backend(:console)
  Logger.remove_backend(JsonRpc.Backend)
end
