defmodule Lexical.RemoteControl.CompileTracer do
  defmodule State do
    require Logger

    @tables ~w(modules calls)a

    for table <- @tables do
      defp table_name(unquote(table)) do
        :"#{__MODULE__}:#{unquote(table)}"
      end
    end

    def create_tables() do
      for table <- @tables do
        table_name = table_name(table)

        :ets.new(table_name, [
          :named_table,
          :public,
          read_concurrency: true,
          write_concurrency: true
        ])
      end

      :ok
    end

    def set_project_dir(project_dir, recent_project_dir) do
      :ok = close_and_sync(recent_project_dir)

      {us, _} =
        :timer.tc(fn ->
          for table <- @tables, do: init_table(project_dir, table)
        end)

      Logger.info("Loaded DETS databases in #{div(us, 1000)}ms")

      {:ok, project_dir}
    end

    def close_and_sync(nil) do
      :ok
    end

    def close_and_sync(project_dir) do
      for table <- @tables do
        table_name = table_name(table)
        :ets.delete_all_objects(table_name)
      end

      for table <- @tables, do: close_and_sync_dets(project_dir, table)

      :ok
    end

    defp init_table(project_dir, table) do
      table_name = table_name(table)
      project_dets_path = dets_path(project_dir, table)

      {:ok, _} =
        :dets.open_file(table_name,
          file: String.to_charlist(project_dets_path),
          auto_save: 60_000
        )

      case :dets.to_ets(table_name, table_name) do
        ^table_name ->
          :ok

        {:error, reason} ->
          Logger.error("Unable to load DETS #{project_dets_path}, #{inspect(reason)}")
          :error
      end
    end

    def in_project_sources?(project_dir, path) do
      topmost_path_segment =
        path
        |> Path.relative_to(project_dir)
        |> Path.split()
        |> hd

      topmost_path_segment != "deps"
    end

    def register_call(callee, meta, env) do
      line = meta[:line]
      column = meta[:column]
      true = :ets.insert(table_name(:calls), {{callee, env.file, line, column, env.aliases}, :ok})
      :ok
    end

    def register_module(module, info) do
      true = :ets.insert(table_name(:modules), {module, info})
      :ok
    end

    @doc """
    Return the module info for the given module name.

    Examples:
      iex> get_moudle_info_by_name(Lexi.Tracer.State)
    """
    def get_moudle_info_by_name(name) do
      ms = [{{:"$1", :"$2"}, [{:==, :"$1", name}], [:"$2"]}]

      case :ets.select(table_name(:modules), ms) do
        [info] -> info
        [] -> nil
      end
    end

    @doc """
    Returns a def location info: `%{file: file, range: range}`
    """
    def get_def_info_by_mfa({m, f, a}) do
      module_info = get_moudle_info_by_name(m)

      if module_info do
        module_info[:defs]
        |> Enum.find_value(fn {{def, arity}, info} ->
          if def == f and arity == a do
            %{file: module_info[:file], range: info[:range]}
          end
        end)
      end
    end

    @doc """
    Return a list of `{module, info}` tuples for all modules in the given file.
    """
    def list_modules_by_file(file) do
      # ms = :ets.fun2ms(fn {_, map} when :erlang.map_get(:file, map) == file -> map end)
      ms = modules_by_file_matchspec(file, :"$_")
      :ets.select(table_name(:modules), ms)
    end

    def get_module_range_by_file_and_line(file, line) do
      list_modules_by_file(file)
      |> Enum.sort_by(fn {_, info} -> info[:line] end, :desc)
      |> Enum.find_value(fn {_, info} ->
        if line >= info[:line] do
          info[:range]
        end
      end)
    end

    @doc """
    Return a list of `%{callee: callee, file: file, line: line, column: column}` for all calls in the given file.

    opts support `reject_no_column`, default is false.
    """
    def list_calls_by_file(file, opts \\ []) do
      ms = calls_by_file_matchspec(file, :"$_", opts)

      for {{callee, file, line, column, _}, _} <- :ets.select(table_name(:calls), ms),
          do: %{callee: callee, file: file, line: line, column: column}
    end

    @doc """
    Return a list of `%{file: file, line: line, column: column}` maps for all calls in the given `callee(m, f, a)`
    """
    def list_calls_by_callee({m, f, a}) do
      # :ets.fun2ms(fn {{m, f, a}, _, _, _} = x when m == :m and f == :f and a == :a -> x end)
      ms = [
        {{{{:"$1", :"$2", :"$3"}, :"$4", :"$5", :"$6", :_}, :_},
         [
           {:andalso, {:andalso, {:==, :"$1", m}, {:==, :"$2", f}}, {:==, :"$3", a}}
         ], [:"$_"]}
      ]

      for {{_, file, line, column, _}, _} <- :ets.select(table_name(:calls), ms),
          do: %{file: file, line: line, column: column}
    end

    @doc """
    Returns a call by the given file and position.
    """
    def get_call_by_file_and_position(file, {line, column}) do
      # :ets.fun2ms(fn {{_, file, line, column}, _} = x when file == file and line == line and column == column -> x end)
      ms = [
        {{{:_, :"$1", :"$2", :"$3", :_}, :_},
         [
           {:andalso, {:andalso, {:==, :"$1", file}, {:==, :"$2", line}}, {:==, :"$3", column}}
         ], [:"$_"]}
      ]

      :ets.select(table_name(:calls), ms)
      |> Enum.map(fn {{callee, file, line, column, _}, _} ->
        %{callee: callee, file: file, line: line, column: column}
      end)
      |> List.first()
    end

    @doc """
    Return the a map `%{<aliased> => <source>}`for the given call `file` and `line`
    """
    def get_alias_mapping_by_file_and_line(file, line) do
      # :ets.fun2ms(fn {_, %{file: file, line: line, aliases: aliases}} when file == :file and line <= :line -> aliases end)
      ms = [
        {{{:_, :"$1", :"$2", :"$3", :"$4"}, :_},
         [
           {:andalso, {:==, :"$1", file}, {:==, :"$2", line}}
         ], [:"$4"]}
      ]

      :ets.select(table_name(:calls), ms)
      |> Enum.reject(&is_nil/1)
      |> List.flatten()
      |> Map.new()
    end

    def clean_dets(project_dir) do
      dets_glob = Path.join([project_dir, ".lexical/*.dets"])
      for path <- Path.wildcard(dets_glob), do: File.rm_rf!(path)
    end

    def delete_modules_by_file(file) do
      ms = modules_by_file_matchspec(file, true)
      # ms = :ets.fun2ms(fn {_, map} when :erlang.map_get(:file, map) == file -> true end)

      :ets.select_delete(table_name(:modules), ms)
    end

    def delete_calls_by_file(file) do
      # ms = calls_by_file_matchspec(file, true, [])
      ms = calls_by_file_matchspec(file, true, [])

      :ets.select_delete(table_name(:calls), ms)
    end

    defp close_and_sync_dets(project_dir, table) do
      path = dets_path(project_dir, table)
      table_name = table_name(table)
      sync(table_name)

      case :dets.close(table_name) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.error("Unable to close DETS #{path}, #{inspect(reason)}")
      end
    end

    defp sync(table_name) do
      with :ok <- :dets.from_ets(table_name, table_name),
           :ok <- :dets.sync(table_name) do
        :ok
      else
        {:error, reason} ->
          Logger.error("Unable to sync DETS #{table_name}, #{inspect(reason)}")
      end
    end

    defp dets_path(project_dir, table) do
      Path.join([project_dir, ".lexical", "#{table}.dets"])
    end

    defp modules_by_file_matchspec(file, return) do
      [
        {{:"$1", :"$2"},
         [
           {
             :andalso,
             {:andalso, {:==, {:map_get, :file, :"$2"}, file}}
           }
         ], [return]}
      ]
    end

    defp calls_by_file_matchspec(file, return, opts) do
      if opts[:reject_no_column] do
        # :ets.fun2ms(fn {{_, file, _, column}, _} = x when file == file and not is_nil(column) -> x end)
        [
          {{{:_, :"$1", :"$2", :"$3", :_}, :_},
           [{:andalso, {:==, :"$1", file}, {:not, {:==, :"$3", nil}}}], [return]}
        ]
      else
        [
          {{{:_, :"$1", :_, :_, :_}, :_}, [{:==, :"$1", file}], [return]}
        ]
      end
    end
  end

  @moduledoc """
  """
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.ModuleMappings
  alias Lexical.CompileTracer.Builder

  import RemoteControl.Api.Messages
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
    message = extract_module_updated(env.module)
    ModuleMappings.update(env.module, env.file)
    RemoteControl.notify_listener(message)
    info = Builder.build_module_info(env.module, env.file, env.line)
    :ok = State.register_module(env.module, info)
    :ok
  end

  def trace(_event, _env) do
    :ok
  end

  def extract_module_updated(module) do
    functions = module.__info__(:functions)
    macros = module.__info__(:macros)

    struct =
      if function_exported?(module, :__struct__, 0) do
        module.__struct__()
        |> Map.from_struct()
        |> Enum.map(fn {k, v} ->
          %{field: k, required?: !is_nil(v)}
        end)
      end

    module_updated(
      name: module,
      functions: functions,
      macros: macros,
      struct: struct
    )
  end
end

