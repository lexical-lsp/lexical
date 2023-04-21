defmodule Lexical.RemoteControl.ProjectNode do
  use GenServer

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, [])
  end

  def init(options) do
    wait_boot = options[:wait_boot] || 5_000
    send(self(), :start_remote_control)
    {:ok, %{options: options, wait_boot: wait_boot}}
  end

  def handle_info(:start_remote_control, state) do
    options = state[:options]

    cmd =
      "elixir -pa #{options[:paths]} --name #{options[:name]} --cookie #{options[:cookie]} --no-halt"

    case System.shell(cmd) do
      {_, 0} ->
        {:noreply, state}

      _ ->
        {:stop, :boot_failed, state}
    end
  end
end
