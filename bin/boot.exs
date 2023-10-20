script_dir = __DIR__

Enum.each(["consolidated", "config", "priv"], fn dir ->
  [script_dir, "..", dir]
  |> Path.join()
  |> Code.append_path()
end)

[script_dir, "..", "lib", "*.ez"]
|> Path.join()
|> Path.wildcard()
|> Enum.each(fn archive_path ->
  lib =
    archive_path
    |> Path.basename()
    |> String.replace_suffix(".ez", "")

  [archive_path, lib, "ebin"]
  |> Path.join()
  |> Code.append_path()
end)

LXical.Server.Boot.start()

if System.get_env("LX_HALT_AFTER_BOOT") do
  require Logger
  Logger.warning("Shutting down (LX_HALT_AFTER_BOOT)")
  System.halt()
end
