import Config

cond do
  Code.ensure_loaded?(LoggerFileBackend) ->
    log_directory = Path.join(File.cwd!(), ".lexical")

    unless File.exists?(log_directory) do
      File.mkdir_p(log_directory)
    end

    log_file_name = Path.join(log_directory, "lexical.log")

    config :logger,
      handle_sasl_reports: true,
      handle_otp_reports: true,
      backends: [{LoggerFileBackend, :general_log}]

    config :logger, :general_log,
      path: log_file_name,
      level: :debug

  Code.ensure_loaded?(JsonRpcBackend) ->
    config :logger,
      backends: [JsonRpcBackend]

    config :logger, JsonRpcBackend,
      level: :error,
      format: "$message",
      metadata: []

  true ->
    :ok
end
