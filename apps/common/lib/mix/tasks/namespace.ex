defmodule Mix.Tasks.Namespace do
  alias Mix.Tasks.Namespace.Transform

  use Mix.Task

  def run(_) do
    app_names =
      for {module, _} <- Mix.Project.apps_paths() do
        module
      end

    app_globs = "{" <> Enum.join(app_names, ",") <> "}"

    beam_files =
      [Mix.Project.build_path(), "lib", app_globs, "**", "ebin", "Elixir.Lexical.*.beam"]
      |> Path.join()
      |> Path.wildcard()

    Enum.each(beam_files, fn beam_file ->
      Transform.transform(beam_file)
      IO.write(".")
    end)

    Mix.Shell.IO.info("\nRewrite Complete. Generating apps")
    Mix.Task.rerun("compile.app")
  end
end
