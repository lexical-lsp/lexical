defmodule Lexical.RemoteControl.Build.Document do
  alias Lexical.Document
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.Build.Document.Compilers

  @compilers [Compilers.Config, Compilers.Elixir, Compilers.EEx, Compilers.HEEx, Compilers.NoOp]

  def compile(%Document{} = document) do
    compiler = Enum.find(@compilers, & &1.recognizes?(document))
    me = self()

    {pid, ref} =
      spawn_monitor(fn ->
        result = compiler.compile(document)
        send(me, {:result, result})
      end)

    receive do
      {:result, result} ->
        flush_normal_down(ref, pid)
        result

      {:DOWN, ^ref, :process, ^pid, {exception, stack}} ->
        diagnostic = Build.Error.error_to_diagnostic(document, exception, stack, nil)
        diagnostics = Build.Error.refine_diagnostics([diagnostic])
        {:error, diagnostics}
    end
  end

  defp flush_normal_down(ref, pid) do
    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} ->
        :ok
    end
  end
end
