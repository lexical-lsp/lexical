defmodule Lexical.RemoteControl.Completion.Struct do
  require Logger

  def doc(full_name) when is_binary(full_name) do
    struct = Module.concat(Elixir, full_name)

    case fetch_struct_type(struct) do
      {:ok, t} ->
        default = default_key_values(struct)

        t
        |> Macro.to_string()
        |> trim_parent(full_name)
        |> maybe_put_default(default)
        |> replace_default_symbol()

      _ ->
        "#{inspect(struct.__struct__(), pretty: true, width: 40)}"
        |> trim_parent(full_name)
    end
  end

  defp fetch_struct_type(struct) do
    with {:ok, types} <- Code.Typespec.fetch_types(struct),
         {:type, t} <- Enum.find(types, &match?({:type, {:t, _, _}}, &1)) do
      {:ok, Code.Typespec.type_to_quoted(t)}
    end
  end

  defp maybe_put_default(doc, []) do
    doc
    |> Sourceror.parse_string!()
    |> to_pretty_string()
  end

  defp maybe_put_default(doc, default_key_values) do
    doc
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      {{:__block__, _, [key_name]} = key, value} ->
        if key_name in Keyword.keys(default_key_values) do
          value_string = Sourceror.to_string(value, locals_without_parens: [])

          new_value =
            "#{value_string} || #{inspect(default_key_values[key_name])}"
            |> Sourceror.parse_string!()

          {key, new_value}
        else
          {key, value}
        end

      quoted ->
        quoted
    end)
    |> to_pretty_string()
  end

  defp default_key_values(struct) do
    for {key, value} <- Map.from_struct(struct.__struct__), not is_nil(value) do
      {key, value}
    end
  end

  defp to_pretty_string(quoted) do
    Sourceror.to_string(quoted, locals_without_parens: [], line_length: 40)
  end

  defp trim_parent(doc, full_name) do
    parent_module = full_name |> String.split(".") |> Enum.slice(0..-2) |> Enum.join(".")

    doc
    |> String.replace("%#{parent_module}.", "%")
    |> String.replace(" #{parent_module}.", " ")
  end

  defp replace_default_symbol(doc) do
    String.replace(doc, "||", "\\\\")
  end
end
