defmodule Lexical.RemoteControl.Tracer do
  @moduledoc """
  """
  alias Lexical.RemoteControl.Tracer.Builder
  alias Lexical.RemoteControl.Tracer.State
  require Logger

  use GenServer

  def set_project_dir(project_dir) do
    GenServer.call(__MODULE__, {:set_project_dir, project_dir})
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    :ok = State.create_tables()
    {:ok, %{project_dir: nil}}
  end

  @impl true
  def handle_call({:set_project_dir, project_dir}, _from, %{project_dir: recent_project} = state) do
    {:ok, project_dir} = State.set_project_dir(project_dir, recent_project)
    {:reply, :ok, %{state | project_dir: project_dir}}
  end

  @impl true
  def terminate(_reason, state) do
    :ok = State.close_and_sync(state.project_dir)
    :ok
  end

  def trace(:start, %Macro.Env{} = env) do
    State.delete_modules_by_file(env.file)
    State.delete_calls_by_file(env.file)

    :ok
  end

  @remote ~w[
      imported_function
      remote_function
      imported_macro
      remote_macro
    ]a

  def trace({kind, meta, module, name, arity}, %Macro.Env{} = env) when kind in @remote do
    callee = {module, name, arity}
    :ok = State.register_call(callee, meta, env)
    :ok
  end

  @local ~w[
      local_function
      local_macro
    ]a

  def trace({kind, meta, name, arity}, %Macro.Env{} = env) when kind in @local do
    callee = {env.module, name, arity}
    :ok = State.register_call(callee, meta, env)
    :ok
  end

  def trace({:alias, meta, module, _as, _opts}, %Macro.Env{} = env) do
    # it will trace `require ... as` too
    callee_module = {module, nil, nil}
    :ok = State.register_call(callee_module, meta, env)

    :ok
  end

  def trace({:alias_expansion, meta, _as, alias}, %Macro.Env{} = env) do
    callee_module = {alias, nil, nil}
    :ok = State.register_call(callee_module, meta, env)

    :ok
  end

  def trace({:alias_reference, meta, module}, %Macro.Env{} = env) do
    callee_module = {module, nil, nil}
    :ok = State.register_call(callee_module, meta, env)
    :ok
  end

  @require_or_import ~w[
      require
      import
    ]a

  def trace({kind, meta, module, _opts}, %Macro.Env{} = env) when kind in @require_or_import do
    callee_module = {module, nil, nil}
    :ok = State.register_call(callee_module, meta, env)
    :ok
  end

  def trace({:on_module, _, _}, %Macro.Env{} = env) do
    info = Builder.build_module_info(env.module, env.file, env.line)

    if info do
      :ok = State.register_module(env.module, info)
    end

    :ok
  end

  def trace(_event, _env) do
    :ok
  end
end
