defmodule Mix.Tasks.Namespace.Transform do
  alias Mix.Tasks.Namespace.Abstract
  alias Mix.Tasks.Namespace.Code

  def transform(path) do
    erlang_path = String.to_charlist(path)

    with {:ok, forms} <- abstract_code(erlang_path),
         rewritten_forms = Abstract.rewrite(forms),
         {:ok, module_name, binary} <- Code.compile(rewritten_forms) do
      write_module_beam(path, module_name, binary)
    end
  end

  defp write_module_beam(old_path, module_name, binary) do
    ebin_path = Path.dirname(old_path)
    new_beam_path = Path.join(ebin_path, "#{module_name}.beam")

    with :ok <- File.write(new_beam_path, binary, [:binary, :raw]) do
      unless old_path == new_beam_path do
        # avoids deleting modules that did not get a new name
        # e.g. Elixir.Mix.Task.. etc
        File.rm(old_path)
      end
    end
  end

  defp abstract_code(path) do
    with {:ok, {_orig_module, code_parts}} <- :beam_lib.chunks(path, [:abstract_code]),
         {:ok, {:raw_abstract_v1, forms}} <- Keyword.fetch(code_parts, :abstract_code) do
      {:ok, forms}
    else
      _ ->
        {:error, :not_found}
    end
  end
end
