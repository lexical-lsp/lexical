defmodule Mix.Tasks.Namespace.Module do
  alias Mix.Tasks.Namespace

  @apps_to_rewrite Namespace.Task.apps_to_namespace() -- ~w(proto protocol server)a

  def rewrite(module_name) when module_name in @apps_to_rewrite do
    :"lx_#{module_name}"
  end

  def rewrite(module_name) do
    module_name
    |> Atom.to_string()
    |> String.split(".")
    |> maybe_rewrite_split_module(module_name)
  end

  @lexical "Lexical"

  defp maybe_rewrite_split_module([@lexical], _) do
    LXRelease
  end

  @deps_to_namespace ~w(Sourceror PathGlob)s

  defp maybe_rewrite_split_module(["Elixir" | rest], _) do
    rest
    |> Enum.map(fn
      @lexical ->
        "LXRelease"

      name when name in @deps_to_namespace ->
        "LX#{name}"

      other ->
        other
    end)
    |> Module.concat()
  end

  defp maybe_rewrite_split_module(_, erlang_module) do
    erlang_module
  end
end
