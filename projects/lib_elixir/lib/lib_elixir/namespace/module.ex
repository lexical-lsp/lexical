defmodule LibElixir.Namespace.Module do
  alias LibElixir.Namespace

  def apply(module_name) when is_binary(module_name) do
    module_name |> String.to_atom() |> apply()
  end

  def apply(module_name) do
    cond do
      prefixed?(module_name) ->
        module_name

      module_name in Namespace.app_names() ->
        :"#{Namespace.erlang_namespace()}#{module_name}"

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

  def prefixed?("Elixir." <> rest), do: prefixed?(rest)
  def prefixed?(list) when is_list(list), do: prefixed?(List.to_string(list))

  def prefixed?(name) when is_binary(name) do
    elixir_namespace = Namespace.elixir_namespace()
    erlang_namespace = Namespace.erlang_namespace()

    String.starts_with?(name, elixir_namespace) or String.starts_with?(name, erlang_namespace)
  end

  defp apply_namespace("Elixir." <> rest) do
    Namespace.elixir_root_modules()
    |> Enum.map(fn root_module -> root_module |> Module.split() |> List.first() end)
    |> Enum.reduce_while(rest, fn root_module, module ->
      if has_root_module?(root_module, module) do
        namespaced_module =
          case split_on_protocol(module) do
            {prefix, suffix} ->
              "Elixir." <> namespaced_suffix =
                Atom.to_string(apply("Elixir." <> suffix))

              namespaced_prefix =
                String.replace(prefix, root_module, namespace(root_module), global: false)

              namespaced_prefix <> namespaced_suffix

            nil ->
              String.replace(module, root_module, namespace(root_module), global: false)
          end

        {:halt, String.to_atom(namespaced_module)}
      else
        {:cont, module}
      end
    end)
    |> List.wrap()
    |> Module.concat()
  end

  # special case for Elixir code server ETS table
  defp apply_namespace("elixir_modules") do
    :"#{Namespace.erlang_namespace()}elixir_modules"
  end

  defp apply_namespace(erlang_module) do
    Namespace.erlang_root_modules()
    |> Enum.map(&Atom.to_string/1)
    |> Enum.reduce_while(erlang_module, fn
      module, module -> {:halt, Namespace.erlang_namespace() <> module}
      _, module -> {:cont, module}
    end)
    |> String.to_atom()
  end

  defp has_root_module?(root_module, root_module), do: true

  defp has_root_module?(root_module, candidate) do
    String.starts_with?(candidate, root_module <> ".")
  end

  defp namespace(orig) do
    Namespace.elixir_namespace() <> orig
  end

  defp split_on_protocol(module_name) do
    Enum.find_value(builtin_protocols(), fn proto ->
      if String.starts_with?(module_name, proto) do
        [_, rest] = String.split(module_name, proto, parts: 2)
        {proto, rest}
      end
    end)
  end

  defp builtin_protocols do
    ["Enumerable.", "Collectable.", "Inspect.", "List.Chars.", "String.Chars."]
  end
end
