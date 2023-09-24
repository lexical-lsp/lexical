defmodule Lexical.Server.Boot do
  @moduledoc """
  This module is called when the server starts by the start script.

  Packaging will ensure that config.exs and runtime.exs will be visible to the `:code` module
  """
  alias Lexical.VM.Versions
  require Logger

  # halt/1 will generate a "no local return" error, which is exactly right, but that's it's _job_
  @dialyzer {:nowarn_function, halt: 1}

  @env Mix.env()
  @target Mix.target()
  @dep_apps Enum.map(Mix.Dep.cached(), & &1.app)

  def start do
    {:ok, _} = Application.ensure_all_started(:mix)
    Application.stop(:logger)
    load_config()
    Application.ensure_all_started(:logger)

    Enum.each(@dep_apps, &load_app_modules/1)
    verify_packaging()
    verify_versioning()
    Application.ensure_all_started(:server)
  end

  defp load_config do
    config = read_config("config.exs")
    runtime = read_config("runtime.exs")
    merged_config = Config.Reader.merge(config, runtime)
    apply_config(merged_config)
  end

  defp apply_config(configs) do
    for {app_name, keywords} <- configs,
        {config_key, config_value} <- keywords do
      Application.put_env(app_name, config_key, config_value)
    end
  end

  defp read_config(file_name) do
    case where_is_file(String.to_charlist(file_name)) do
      {:ok, path} ->
        Config.Reader.read!(path, env: @env, target: @target)

      _ ->
        []
    end
  end

  defp where_is_file(file_name) do
    case :code.where_is_file(file_name) do
      :non_existing ->
        :error

      path ->
        {:ok, List.to_string(path)}
    end
  end

  defp load_app_modules(app_name) do
    Application.ensure_loaded(app_name)

    with {:ok, modules} <- :application.get_key(app_name, :modules) do
      Enum.each(modules, &Code.ensure_loaded!/1)
    end
  end

  defp verify_packaging do
    unless Versions.compatible?() do
      {:ok, compiled_versions} = Versions.compiled()

      compiled_versions = Versions.to_versions(compiled_versions)
      current_versions = Versions.current() |> Versions.to_versions()

      compiled_erlang = compiled_versions.erlang
      current_erlang = current_versions.erlang

      message = """
      Lexical failed its version check. This is a FATAL Error!
      Lexical is running on Erlang #{current_erlang} and the compiled files were built on
      Erlang #{compiled_erlang}.

      If you wish to run Lexical under Erlang version #{current_erlang}, you must rebuild lexical
      under an Erlang version that is <= #{current_erlang.major}.

      Detected Lexical running on erlang #{current_erlang.major} and needs >= #{compiled_erlang.major}
      """

      halt(message)

      Process.sleep(500)
      System.halt()
    end
  end

  @allowed_elixir %{
    "1.13.0" => ">= 1.13.4",
    "1.14.0" => ">= 1.14.0",
    "1.15.0" => ">= 1.15.3"
  }
  @allowed_erlang %{
    "24" => ">= 24.3.4",
    "25" => ">= 25.0.0",
    "26" => ">= 26.0.2"
  }

  defp verify_versioning do
    versions = Versions.to_versions(Versions.current())

    elixir_base = to_string(%Version{versions.elixir | patch: 0})
    erlang_base = to_string(versions.erlang.major)

    detected_elixir_range = Map.get(@allowed_elixir, elixir_base)
    detected_erlang_range = Map.get(@allowed_erlang, erlang_base)

    elixir_ok? = Version.match?(versions.elixir, detected_elixir_range)
    erlang_ok? = Version.match?(versions.erlang, detected_erlang_range)

    cond do
      not elixir_ok? ->
        message = """
        The version of elixir lexical found (#{versions.elixir}) is not compatible with lexical,
        and lexical can't start.

        Please change your version of elixir to #{detected_elixir_range}
        """

        halt(message)

      not erlang_ok? ->
        message = """
        The version of erlang lexical found (#{versions.erlang}) is not compatible with lexical,
        and lexical can't start.

        Please change your version of erlang to one of the following: #{detected_erlang_range}
        """

        halt(message)

      true ->
        :ok
    end
  end

  defp halt(message) do
    Mix.Shell.IO.error(message)
    Logger.emergency(message)
    # Wait for the logs to flush
    Process.sleep(500)
    System.halt()
  end
end
