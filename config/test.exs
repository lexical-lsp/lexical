import Config
alias Lexical.Server.JsonRpc
alias Lexical.Test.Transport.NoOp

config :logger, level: :none

config :remote_control,
  edit_window_millis: 10,
  modules_cache_expiry: {50, :millisecond},
  search_store_quiescent_period_ms: 10

config :server, transport: NoOp
config :stream_data, initial_size: 50
