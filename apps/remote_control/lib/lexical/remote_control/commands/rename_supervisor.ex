defmodule Lexical.RemoteControl.Commands.RenameSupervisor do
  alias Lexical.RemoteControl.Commands.Rename
  use DynamicSupervisor

  @dialyzer {:no_return, start_link: 1}

  def child_spec do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []}
    }
  end

  def start_link(_) do
    DynamicSupervisor.start_link(name: __MODULE__, strategy: :one_for_one)
  end

  def start_renaming(uri_with_expected_operation, progress_notification_functions) do
    DynamicSupervisor.start_child(
      __MODULE__,
      Rename.child_spec(uri_with_expected_operation, progress_notification_functions)
    )
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
