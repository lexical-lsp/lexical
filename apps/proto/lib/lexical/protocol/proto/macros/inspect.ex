defmodule Lexical.Protocol.Proto.Macros.Inspect do
  def build(dest_module) do
    trimmed_name = trim_module_name(dest_module)

    quote location: :keep do
      defimpl Inspect, for: unquote(dest_module) do
        import Inspect.Algebra

        def inspect(proto_type, opts) do
          proto_map =
            proto_type
            |> Map.from_struct()
            |> Enum.reject(fn {k, v} -> is_nil(v) end)
            |> Map.new()

          concat(["%#{unquote(trimmed_name)}{", to_doc(proto_map, opts), "}"])
        end
      end
    end
  end

  def trim_module_name(long_name) do
    {sub_modules, _} =
      long_name
      |> Module.split()
      |> Enum.reduce({[], false}, fn
        "Protocol", _ ->
          {["Protocol"], true}

        _ignored_module, {_, false} = state ->
          state

        submodule, {mod_list, true} ->
          {[submodule | mod_list], true}
      end)

    sub_modules
    |> Enum.reverse()
    |> Enum.join(".")
  end
end
