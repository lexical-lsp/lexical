defmodule Mix.Tasks.Namespace do
  alias Mix.Tasks.Namespace.Transform

  use Mix.Task

  def run(_) do
    app_names =
      for {module, _} <- Mix.Project.apps_paths() do
        module
      end

    app_globs = "{" <> Enum.join(app_names, ",") <> "}"

    module_beams =
      [Mix.Project.build_path(), "lib", app_globs, "**", "ebin", "Elixir.*Lexical*.beam"]
      |> Path.join()
      |> Path.wildcard()

    consolidated_beams =
      [Mix.Project.consolidation_path(), "**", "Elixir.*Lexical*.beam"]
      |> Path.join()
      |> Path.wildcard()

    beam_files = module_beams ++ consolidated_beams

    file_count = length(beam_files)

    beam_files
    |> Enum.with_index()
    |> Enum.each(fn {beam_file, index} ->
      Transform.transform(beam_file)

      IO.write("\r")
      percent_complete = format_percent(index, file_count)

      IO.write("Applying namespace: #{percent_complete} complete")
    end)

    Mix.Shell.IO.info("\nNamspace applied. Generating apps")
    Mix.Task.rerun("compile.app")
  end

  defp format_percent(current, max) do
    int_val =
      (current / max * 100)
      |> round()
      |> Integer.to_string()

    String.pad_leading("#{int_val}%", 4)
  end
end
