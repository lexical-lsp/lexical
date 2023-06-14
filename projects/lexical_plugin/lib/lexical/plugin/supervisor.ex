defmodule Lexical.Plugin.Supervisor do
  @moduledoc false

  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {Task.Supervisor, :start_link, [[name: __MODULE__]]}
    }
  end

  def async(plugin_module, subject) do
    Task.Supervisor.async_nolink(__MODULE__, plugin_module, :diagnose, [subject])
  end
end
