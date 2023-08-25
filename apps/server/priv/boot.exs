[__DIR__, "..", "lib", "*.ez"]
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
