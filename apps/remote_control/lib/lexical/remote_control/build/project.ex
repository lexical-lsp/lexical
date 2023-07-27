defmodule Lexical.RemoteControl.Build.Project do
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.Plugin

  use Build.Progress
  require Logger

  def compile(%Project{} = project, force?) do
    RemoteControl.Mix.in_project(fn _ ->
      Mix.Task.clear()

      prepare_for_project_build(force?)

      compile_fun = fn ->
        Mix.Task.clear()

        with_progress building_label(project), fn ->
          result = Mix.Task.run(:compile, mix_compile_opts(force?))
          Mix.Task.run(:loadpaths)
          result
        end
      end

      case compile_fun.() do
        {:error, diagnostics} ->
          diagnostics =
            diagnostics
            |> List.wrap()
            |> Build.Error.refine_diagnostics()

          {:error, diagnostics}

        {status, diagnostics} when status in [:ok, :noop] ->
          Logger.info(
            "Compile completed with status #{status} " <>
              "Produced #{length(diagnostics)} diagnostics " <>
              inspect(diagnostics)
          )

          Build.Error.refine_diagnostics(diagnostics)
      end
    end)
  end

  defp prepare_for_project_build(false = _force?) do
    :ok
  end

  defp prepare_for_project_build(true = _force?) do
    if connected_to_internet?() do
      with_progress "mix local.hex", fn ->
        Mix.Task.run("local.hex", ~w(--force --if-missing))
      end

      with_progress "mix local.rebar", fn ->
        Mix.Task.run("local.rebar", ~w(--force --if-missing))
      end

      with_progress "mix deps.get", fn ->
        Mix.Task.run("deps.get")
      end
    else
      Logger.warning("Could not connect to hex.pm, dependencies will not be fetched")
    end

    with_progress "mix loadconfig", fn ->
      Mix.Task.run(:loadconfig)
    end

    with_progress "mix deps.compile", fn ->
      deps_compile =
        if Features.compile_wont_change_directory?() do
          "deps.compile"
        else
          "deps.safe_compile"
        end

      Mix.Task.run(deps_compile, ~w(--skip-umbrella-children))
    end

    with_progress "loading plugins", fn ->
      Plugin.Discovery.run()
    end

    Mix.Task.run("clean")
  end

  defp connected_to_internet? do
    # While there's no perfect way to check if a computer is connected to the internet,
    # it seems reasonable to gate pulling dependenices on a resolution check for hex.pm.
    # Yes, it's entirely possible that the DNS server is local, and that the entry is in cache,
    # but that's an edge case, and the build will just time out anyways.
    case :inet_res.getbyname(~c"hex.pm", :a, 250) do
      {:ok, _} -> true
      _ -> false
    end
  end

  def building_label(%Project{} = project) do
    "Building #{Project.display_name(project)}"
  end

  defp mix_compile_opts(force?) do
    opts = ~w(
        --return-errors
        --ignore-module-conflict
        --all-warnings
        --docs
        --debug-info
        --no-protocol-consolidation
    )

    if force? do
      ["--force " | opts]
    else
      opts
    end
  end
end
