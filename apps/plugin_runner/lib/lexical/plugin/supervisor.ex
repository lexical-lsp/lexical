defmodule Lexical.Plugin.Runner.Supervisor do
  @moduledoc false

  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {Task.Supervisor, :start_link, [[name: name()]]}
    }
  end

  def async(plugin_module, subject) do
    Task.Supervisor.async_nolink(name(), plugin_module, :diagnose, [subject])
  end

  defp name do
    Module.concat(__MODULE__, TaskSupervisor)
  end
end
