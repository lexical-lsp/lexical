defmodule Lexical.RemoteControl.Plugin.Supervisor do
  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {Task.Supervisor, :start_link, []},
      name: __MODULE__
    }
  end

  def async_nolink(function) do
    Task.Supervisor.async_nolink(__MODULE__, function)
  end
end
