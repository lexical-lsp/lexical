defmodule Mix.Tasks.Namespace.Transform.Configs do
  alias Mix.Tasks.Namespace

  def apply_to_all(base_directory) do
    base_directory
    |> Path.join("**")
    |> Path.wildcard()
    |> Enum.map(&Path.absname/1)
    |> Enum.each(&apply/1)
  end

  def apply(path) do
    namespaced =
      path
      |> File.read!()
      |> Code.string_to_quoted!()
      |> Macro.postwalk(fn
        atom when is_atom(atom) ->
          Namespace.Module.apply(atom)

        ast ->
          ast
      end)
      |> Macro.to_string()

    File.write!(path, namespaced)
  end
end
