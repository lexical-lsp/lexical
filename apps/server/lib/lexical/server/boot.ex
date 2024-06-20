defmodule Lexical.Server.Boot do
  @moduledoc """
  This module is called when the server starts by the start script.

  Packaging will ensure that config.exs and runtime.exs will be visible to the `:code` module
  """
  alias Future.Code
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

    case detect_errors() do
      [] ->
        :ok

      errors ->
        errors
        |> Enum.join("\n\n")
        |> halt()
    end

    Application.ensure_all_started(:server)
  end

  @doc false
  def detect_errors do
    versioning_errors()
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
    modules = Application.spec(app_name, :modules)
    Code.ensure_all_loaded!(modules)
  end

  @allowed_elixir %{
    "1.13.0" => ">= 1.13.0",
    "1.14.0" => ">= 1.14.0",
    "1.15.0" => ">= 1.15.3",
    "1.16.0" => ">= 1.16.0",
    "1.17.0-rc" => ">= 1.17.0-rc",
    "1.17.0" => ">= 1.17.0"
  }
  @allowed_erlang %{
    "24" => ">= 24.3.4",
    "25" => ">= 25.0.0",
    "26" => ">= 26.0.2",
    "27" => ">= 27.0.0"
  }

  defp versioning_errors do
    versions = Versions.to_versions(Versions.current())

    elixir_base = to_string(%Version{versions.elixir | patch: 0})
    erlang_base = to_string(versions.erlang.major)

    detected_elixir_range = Map.get(@allowed_elixir, elixir_base, false)
    detected_erlang_range = Map.get(@allowed_erlang, erlang_base, false)

    elixir_ok? = detected_elixir_range && Version.match?(versions.elixir, detected_elixir_range)
    erlang_ok? = detected_erlang_range && Version.match?(versions.erlang, detected_erlang_range)

    errors = [
      unless elixir_ok? do
        """
        FATAL: Lexical is not compatible with Elixir #{versions.elixir}

        Lexical is compatible with the following versions of Elixir:

        #{format_allowed_versions(@allowed_elixir)}
        """
      end,
      unless erlang_ok? do
        """
        FATAL: Lexical is not compatible with Erlang/OTP #{versions.erlang}

        Lexical is compatible with the following versions of Erlang/OTP:

        #{format_allowed_versions(@allowed_erlang)}
        """
      end
    ]

    Enum.filter(errors, &Function.identity/1)
  end

  defp format_allowed_versions(%{} = versions) do
    versions
    |> Map.values()
    |> Enum.sort()
    |> Enum.map_join("\n", fn range -> "  #{range}" end)
  end

  defp halt(message) do
    Mix.Shell.IO.error(message)
    Logger.emergency(message)
    Logger.flush()
    System.halt()
  end
end
