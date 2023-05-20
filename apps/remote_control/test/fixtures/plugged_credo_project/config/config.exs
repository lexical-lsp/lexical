import Config

if config_env() in [:dev, :test] do
  config :lexical, :plugins, [Lexical.Credo]
end
