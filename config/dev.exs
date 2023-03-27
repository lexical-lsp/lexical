import Config

umbrella_root = File.cwd!()
config :remote_control, umbrella_root: umbrella_root

defmodule Mix.Tasks.Compile.Namespace do
  def namespace_modules(ast) do
    Macro.prewalk(ast, fn
      {:__aliases__, meta, [:Lexical | rest]} ->
        {:__aliases__, meta, [:LexicalNamespace | rest]}

      any ->
        any
    end)
  end

  def write_namespaced_file(path, string) do
    # Example:
    #   original path:
    #       apps/remote_control/mix.exs
    #   out_path:
    #       _build/dev/namespaced/apps/remote_control/mix.exs
    out_path = Path.join([Mix.Project.build_path(), "namespaced", path])
    :ok = File.mkdir_p(Path.dirname(out_path))
    :ok = File.write(out_path, string)
    out_path
  end

  def run(_args) do
    # First, clear previous build.
    File.rm_rf(Path.join([Mix.Project.build_path(), "namespaced"]))
    # Get all paths for common, common_protocol and remote_control.
    # Get /lib only. If we get /test we end up with fixtures for
    # code that has errors and it fails on Code.string_to_quoted()
    apps = "apps/{remote_control,common,common_protocol,proto}"

    paths =
      Path.wildcard(apps <> "/lib/**/*.{ex,exs}") ++
        Path.wildcard(apps <> "/mix.exs") ++
        Path.wildcard("mix.exs")

    _files =
      Enum.map(paths, fn p ->
        with {:ok, string} <- File.read(p),
             {:ok, quoted} <- Code.string_to_quoted(string) do
          new_quoted = namespace_modules(quoted)
          new_string = Macro.to_string(new_quoted)
          write_namespaced_file(p, new_string)
        else
          err ->
            raise CompileError.exception(
                    description: inspect(err),
                    file: p
                  )
        end
      end)

    # Process the modified source files.
    # Treat them as their own umbrella app to be as consistent as possible.
    cd_path = Path.join([Mix.Project.build_path(), "namespaced"])
    File.cd(cd_path)
    Mix.Task.run("deps.get")
    Mix.Task.run("compile")
  end
end
