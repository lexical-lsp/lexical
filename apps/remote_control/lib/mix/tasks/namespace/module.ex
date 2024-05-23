defmodule Mix.Tasks.Namespace.Module do
  alias Mix.Tasks.Namespace

  @namespace_prefix "LX"

  def apply(module_name) do
    cond do
      prefixed?(module_name) ->
        module_name

      module_name in Namespace.app_names() ->
        :"lx_#{module_name}"

      true ->
        module_name
        |> Atom.to_string()
        |> apply_namespace()
    end
  end

  def prefixed?(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> prefixed?()
  end

  def prefixed?("Elixir." <> rest),
    do: prefixed?(rest)

  def prefixed?(@namespace_prefix <> _),
    do: true

  def prefixed?("lx_" <> _),
    do: true

  def prefixed?([?l, ?x, ?_ | _]), do: true
  def prefixed?([?E, ?l, ?i, ?x, ?i, ?r, ?., ?L, ?X | _]), do: true
  def prefixed?([?L, ?X | _]), do: true

  def prefixed?(_),
    do: false

  defp apply_namespace("Elixir." <> rest) do
    Namespace.root_modules()
    |> Enum.map(fn module -> module |> Module.split() |> List.first() end)
    |> Enum.reduce_while(rest, fn root_module, module ->
      if has_root_module?(root_module, module) do
        namespaced_module =
          module
          |> String.replace(root_module, namespace(root_module), global: false)
          |> String.to_atom()

        {:halt, namespaced_module}
      else
        {:cont, module}
      end
    end)
    |> List.wrap()
    |> Module.concat()
  end

  defp apply_namespace(erlang_module) do
    String.to_atom(erlang_module)
  end

  defp has_root_module?(root_module, root_module), do: true

  defp has_root_module?(root_module, candidate) do
    String.contains?(candidate, append_trailing_period(root_module))
  end

  defp namespace("Lexical") do
    "#{@namespace_prefix}ical"
  end

  defp namespace(orig) do
    @namespace_prefix <> orig
  end

  defp append_trailing_period(str) do
    str <> "."
  end
end
