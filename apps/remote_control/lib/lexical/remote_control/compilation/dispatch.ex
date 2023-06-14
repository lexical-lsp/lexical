defmodule Lexical.RemoteControl.Compilation.Dispatch do
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.ModuleMappings

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
    relative_path_elements =
      file
      |> Path.relative_to_cwd()
      |> Path.split()

    base_dir = List.first(relative_path_elements)
    file_name = List.last(relative_path_elements)

    message = "compiling: " <> Path.join([base_dir, "...", file_name])

    label = Build.State.building_label(RemoteControl.get_project())
    project_progress(label: label, message: message)
  end
end
