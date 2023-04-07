defmodule Mix.Tasks.Hooks do
  def run(_) do
    sources =
      [File.cwd!(), "hooks", "**"]
      |> Path.join()
      |> Path.wildcard()

    sources_count = length(sources)
    hook_text = pluralize(sources_count, "hook", "hooks")
    Mix.Shell.IO.info("Copying #{sources_count} #{hook_text}")
    dest_dir = Path.join([File.cwd!(), ".git", "hooks"])

    for source <- sources,
        dest_path = Path.join(dest_dir, Path.basename(source)) do
      if File.exists?(dest_path) do
        File.rm(dest_path)
      end

      message =
        case File.cp(source, dest_path) do
          :ok ->
            "  #{Path.basename(source)}: ✅"

          {:error, reason} ->
            "  #{Path.basename(source)} ❌ #{inspect(reason)}"
        end

      Mix.Shell.IO.info(message)
    end
  end

  defp pluralize(count, singular, plural) do
    if count == 1 do
      singular
    else
      plural
    end
  end
end
