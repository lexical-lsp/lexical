import Config

Logger.remove_backend(:console)
config :logger, level: :error
