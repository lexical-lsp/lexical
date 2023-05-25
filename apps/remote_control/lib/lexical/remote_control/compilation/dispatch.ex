defmodule Lexical.RemoteControl.Compilation.Dispatch do
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.RemoteControl.ModuleMappings
  alias Lexical.RemoteControl.Plugin

  import Messages
  use GenServer

  def dispatch(module_updated() = message) do
    GenServer.cast(__MODULE__, {:dispatch, message})
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    {:ok, nil}
  end

  def handle_cast({:dispatch, module_updated() = message}, state) do
    module_updated(name: module_name, file: filename) = message
    ModuleMappings.update(module_name, filename)
    RemoteControl.notify_listener(message)
    Plugin.on_module_updated(module_name)
    maybe_report_progress(filename)
    {:noreply, state}
  end

  defp maybe_report_progress(file) do
    if Path.extname(file) == ".ex" do
      file
      |> progress_message()
      |> RemoteControl.notify_listener()
    end
  end

  defp progress_message(file) do
    relative_path = Path.basename(file)
    message = "compiling: " <> relative_path

    label =
      if String.starts_with?(relative_path, "deps") do
        "mix deps.compile"
      else
        "mix compile"
      end

    project_progress(label: label, message: message)
  end
end
