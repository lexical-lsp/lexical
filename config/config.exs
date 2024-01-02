import Config

config :snowflake,
  machine_id: 1,
  # First second of 2024
  epoch: 1_704_070_800_000

import_config("#{Mix.env()}.exs")
