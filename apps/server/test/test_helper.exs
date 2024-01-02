Application.ensure_all_started(:snowflake)
ExUnit.configure(timeout: :infinity)
ExUnit.start()

if Version.match?(System.version(), ">= 1.15.0") do
  Logger.configure(level: :none)
else
  Logger.remove_backend(:console)
end
