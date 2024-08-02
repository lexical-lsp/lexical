defmodule LibElixir.Namespace.Transform.Beams do
  @moduledoc """
  A transformer that finds and replaces any instance of a module in a .beam file
  """

  alias LibElixir.Namespace
  alias LibElixir.Namespace.Abstract
  alias LibElixir.Namespace.DebugInfo

  def apply_to_all(base_directory) do
    Mix.Shell.IO.info("Rewriting .beam files")
    all_beams = find_beams(base_directory)
    total_files = length(all_beams)
    chunk_size = ceil(total_files / System.schedulers_online())

    Mix.Shell.IO.info(" Found #{total_files} beams")

    me = self()

    all_beams
    |> Enum.chunk_every(chunk_size)
    |> Enum.each(fn chunk ->
      Task.async(fn ->
        Enum.each(chunk, &apply_and_update_progress(&1, me))
      end)
    end)

    block_until_done(0, total_files)
  end

  def apply(path) do
    erlang_path = String.to_charlist(path)

    with {:ok, forms, debug_data} <- abstract_code_and_debug_data(erlang_path),
         rewritten_forms = Abstract.rewrite(forms),
         rewritten_debug_data = DebugInfo.rewrite(debug_data),
         true <- changed?(forms, rewritten_forms),
         {:ok, module_name, binary} <- compile_forms(rewritten_forms, rewritten_debug_data),
         :ok <- write_module_beam(path, module_name, binary, rewritten_debug_data) do
      :ok
    else
      error ->
        raise "Failed to transform beam: #{path}\n\ngot: #{inspect(error)}"
    end
  end

  def compile_forms(forms, debug_data) do
    :compile.forms(forms, [
      :return_errors,
      :no_spawn_compiler_process,
      debug_info: {Namespace.Module.apply(:elixir_erl), debug_data}
    ])
  end

  defp changed?(same, same), do: false
  defp changed?(_, _), do: true

  defp block_until_done(same, same) do
    Mix.Shell.IO.info("\n done")
  end

  defp block_until_done(current, max) do
    receive do
      :progress -> :ok
    end

    current = current + 1
    IO.write("\r")
    percent_complete = format_percent(current, max)

    IO.write(" Applying namespace: #{percent_complete} complete")
    block_until_done(current, max)
  end

  defp apply_and_update_progress(beam_file, caller) do
    apply(beam_file)
    send(caller, :progress)
  end

  defp find_beams(base_directory) do
    [base_directory, "**", "*.beam"]
    |> Path.join()
    |> Path.wildcard()
  end

  defp write_module_beam(old_path, module_name, binary, debug_info) do
    ebin_path = Path.dirname(old_path)
    new_beam_path = Path.join(ebin_path, "#{module_name}.beam")

    binary_debug_info = :erlang.term_to_binary(debug_info)
    {:ok, _, chunks} = :beam_lib.all_chunks(binary)
    new_chunks = List.keyreplace(chunks, ~c"Dbgi", 0, {~c"Dbgi", binary_debug_info})
    {:ok, binary} = :beam_lib.build_module(new_chunks)

    with :ok <- File.write(new_beam_path, binary, [:binary, :raw]) do
      if old_path == new_beam_path do
        :ok
      else
        # avoids deleting modules that did not get a new name
        # e.g. Elixir.Mix.Task.. etc
        File.rm(old_path)
      end
    end
  end

  defp abstract_code_and_debug_data(path) do
    with {:ok, {_orig_module, chunks}} <-
           :beam_lib.chunks(path, [:abstract_code, :debug_info]),
         {:raw_abstract_v1, forms} <- chunks[:abstract_code] do
      {:ok, forms, chunks[:debug_info]}
    else
      _ ->
        {:error, :not_found}
    end
  end

  defp format_percent(current, max) do
    int_val =
      (current / max * 100)
      |> round()
      |> Integer.to_string()

    String.pad_leading("#{int_val}%", 4)
  end
end
