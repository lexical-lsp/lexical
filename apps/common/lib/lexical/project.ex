defmodule Lexical.Project do
  @moduledoc """
  The representation of the current state of an elixir project.

  This struct contains all the information required to build a project and interrogate its configuration,
  as well as business logic for how to change its attributes.
  """
  alias Lexical.SourceFile

  defstruct root_uri: nil,
            mix_exs_uri: nil,
            mix_project?: false,
            mix_env: nil,
            mix_target: nil,
            env_variables: %{}

  @type message :: String.t()
  @type restart_notification :: {:restart, Logger.level(), String.t()}
  @type t :: %__MODULE__{
          root_uri: Lexical.uri() | nil,
          mix_exs_uri: Lexical.uri() | nil
          # mix_env: atom(),
          # mix_target: atom(),
          # env_variables: %{String.t() => String.t()}
        }
  @type error_with_message :: {:error, message}

  @workspace_directory_name ".lexical"

  # Public
  @spec new(Lexical.uri()) :: t
  def new(root_uri) do
    %__MODULE__{}
    |> maybe_set_root_uri(root_uri)
    |> maybe_set_mix_exs_uri()
  end

  def name(%__MODULE__{} = project) do
    project
    |> root_path()
    |> Path.split()
    |> List.last()
  end

  @spec root_path(t) :: Path.t() | nil
  def root_path(%__MODULE__{root_uri: nil}) do
    nil
  end

  def root_path(%__MODULE__{} = project) do
    SourceFile.Path.from_uri(project.root_uri)
  end

  @spec project_path(t) :: Path.t() | nil
  def project_path(%__MODULE__{root_uri: nil}) do
    nil
  end

  def project_path(%__MODULE__{} = project) do
    SourceFile.Path.from_uri(project.root_uri)
  end

  @spec mix_exs_path(t) :: Path.t() | nil
  def mix_exs_path(%__MODULE__{mix_exs_uri: nil}) do
    nil
  end

  def mix_exs_path(%__MODULE__{mix_exs_uri: mix_exs_uri}) do
    SourceFile.Path.from_uri(mix_exs_uri)
  end

  @spec change_environment_variables(t, map() | nil) ::
          {:ok, t} | error_with_message() | restart_notification()
  def change_environment_variables(%__MODULE__{} = project, environment_variables) do
    set_env_vars(project, environment_variables)
  end

  def workspace_path(%__MODULE__{} = project) do
    project
    |> root_path()
    |> Path.join(@workspace_directory_name)
  end

  def build_path(%__MODULE__{} = project) do
    project
    |> workspace_path()
    |> Path.join("build")
  end

  def ensure_workspace_exists(%__MODULE__{} = project) do
    workspace_path = workspace_path(project)

    cond do
      File.exists?(workspace_path) and File.dir?(workspace_path) ->
        :ok

      File.exists?(workspace_path) ->
        :ok = File.rm(workspace_path)
        :ok = File.mkdir_p(workspace_path)

      true ->
        :ok = File.mkdir(workspace_path)
    end
  end

  # private

  defp maybe_set_root_uri(%__MODULE__{} = project, nil),
    do: %__MODULE__{project | root_uri: nil}

  defp maybe_set_root_uri(%__MODULE__{} = project, "file://" <> _ = root_uri) do
    root_path =
      root_uri
      |> SourceFile.Path.absolute_from_uri()
      |> Path.expand()

    if File.exists?(root_path) do
      expanded_uri = SourceFile.Path.to_uri(root_path)
      %__MODULE__{project | root_uri: expanded_uri}
    else
      project
    end
  end

  defp maybe_set_mix_exs_uri(%__MODULE__{} = project) do
    possible_mix_exs_path =
      project
      |> root_path()
      |> find_mix_exs_path()

    if mix_exs_exists?(possible_mix_exs_path) do
      %__MODULE__{
        project
        | mix_exs_uri: SourceFile.Path.to_uri(possible_mix_exs_path),
          mix_project?: true
      }
    else
      project
    end
  end

  # Project Path

  # Environment variables

  def set_env_vars(%__MODULE__{} = old_project, %{} = env_vars) do
    case {old_project.env_variables, env_vars} do
      {nil, vars} when map_size(vars) == 0 ->
        {:ok, %__MODULE__{old_project | env_variables: vars}}

      {nil, new_vars} ->
        System.put_env(new_vars)
        {:ok, %__MODULE__{old_project | env_variables: new_vars}}

      {same, same} ->
        {:ok, old_project}

      _ ->
        {:restart, :warning, "Environment variables have changed. Lexical needs to restart"}
    end
  end

  def set_env_vars(%__MODULE__{} = old_project, _) do
    {:ok, old_project}
  end

  defp find_mix_exs_path(nil) do
    System.get_env("MIX_EXS")
  end

  defp find_mix_exs_path(project_directory) do
    case System.get_env("MIX_EXS") do
      nil ->
        Path.join(project_directory, "mix.exs")

      mix_exs ->
        mix_exs
    end
  end

  defp mix_exs_exists?(nil), do: false

  defp mix_exs_exists?(mix_exs_path) do
    File.exists?(mix_exs_path)
  end
end
