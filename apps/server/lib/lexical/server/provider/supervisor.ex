defmodule Lexical.Server.Provider.Queue.Supervisor do
  def name do
    __MODULE__
  end

  def child_spec do
    {Task.Supervisor, name: name()}
  end

  def run_in_task(provider_fn) do
    Task.Supervisor.async_nolink(name(), provider_fn)
  end
end
