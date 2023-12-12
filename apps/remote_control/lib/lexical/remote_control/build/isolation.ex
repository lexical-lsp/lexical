defmodule Lexical.RemoteControl.Build.Isolation do
  @moduledoc """
  Runs functions in an isolated, monitored process
  """

  @spec invoke((() -> term())) :: {:ok, term()} | {:error, term()}
  def invoke(function) when is_function(function, 0) do
    me = self()

    {pid, ref} =
      spawn_monitor(fn ->
        send(me, {:result, function.()})
      end)

    receive do
      {:result, result} ->
        flush_normal_down(ref, pid)
        {:ok, result}

      {:DOWN, ^ref, :process, ^pid, reason} ->
        {:error, reason}
    end
  end

  defp flush_normal_down(ref, pid) do
    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} ->
        :ok
    end
  end
end
