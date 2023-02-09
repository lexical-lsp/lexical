# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config
alias Lexical.Server.JsonRpc.Backend, as: JsonRpcBackend

# Sample configuration:
#
#     config :logger, :console,
#       level: :info,
#       format: "$date $time [$level] $metadata$message\n",
#       metadata: [:user_id]
#

config :logger, backends: [JsonRpcBackend]

config :logger, JsonRpcBackend,
  level: :debug,
  format: "$message",
  metadata: []

import_config("#{Mix.env()}.exs")
