[script_dir] = System.argv()

Path.join([script_dir, "..", "lib", "*.ez"])
|> Path.wildcard()
|> Enum.each(fn archive_path ->
  lib =
    archive_path
    |> Path.basename()
    |> String.replace_suffix(".ez", "")

  true =
  [archive_path, lib, "ebin"]
    |> Path.join()
    |> Code.append_path()
end)

LXical.Server.Boot.start()
