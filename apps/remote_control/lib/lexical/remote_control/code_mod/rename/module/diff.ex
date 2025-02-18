defmodule Lexical.RemoteControl.CodeMod.Rename.Module.Diff do
  def diff(old_name, new_name) do
    with [{:eq, eq} | _] <- String.myers_difference(old_name, new_name),
         equal_segment <- trim_last_dot_part(eq),
         true <- not is_nil(equal_segment) do
      to_be_renamed = replace_leading_eq(old_name, equal_segment)
      replacement = replace_leading_eq(new_name, equal_segment)
      {to_be_renamed, replacement}
    else
      _ ->
        {old_name, new_name}
    end
  end

  defp trim_last_dot_part(module) do
    split = module |> String.reverse() |> String.split(".", parts: 2)

    if length(split) == 2 do
      [_, rest] = split
      rest |> String.reverse()
    end
  end

  defp replace_leading_eq(module, eq) do
    module |> String.replace(~r"^#{eq}", "") |> String.trim_leading(".")
  end
end
