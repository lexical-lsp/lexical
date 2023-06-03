defmodule Mix.Tasks.Namespace.Module do
  alias Mix.Tasks.Namespace

  @deps_to_namespace ~w(Sourceror PathGlob)

  def apply(module_name) do
    apps_to_namespace = Namespace.apps_to_namespace() -- ~w(proto protocol server)a

    if module_name in apps_to_namespace do
      :"lx_#{module_name}"
    else
      module_name
      |> Atom.to_string()
      |> String.split(".")
      |> maybe_namespace_split_module(module_name)
    end
  end

  defp maybe_namespace_split_module(["Lexical"], _) do
    LXRelease
  end

  defp maybe_namespace_split_module(["Elixir" | rest], _) do
    rest
    |> Enum.map(fn
      "Lexical" ->
        "LXRelease"

      name when name in @deps_to_namespace ->
        "LX#{name}"

      other ->
        other
    end)
    |> Module.concat()
  end

  defp maybe_namespace_split_module(_, erlang_module) do
    erlang_module
  end
end
