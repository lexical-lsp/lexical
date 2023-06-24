defmodule Lexical.Project do
  @moduledoc """
  The representation of the current state of an elixir project.

  This struct contains all the information required to build a project and interrogate its configuration,
  as well as business logic for how to change its attributes.
  """
  alias Lexical.Document

  defstruct root_uri: nil,
            mix_exs_uri: nil,
            mix_project?: false,
            mix_env: nil,
            mix_target: nil,
            env_variables: %{},
            project_module: nil

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

  @spec set_project_module(t(), module() | nil) :: t()
  def set_project_module(%__MODULE__{} = project, nil) do
    project
  end

  def set_project_module(%__MODULE__{} = project, module) when is_atom(module) do
    %__MODULE__{project | project_module: module}
  end

  @doc """
  Retrieves the name of the project
  """
  @spec name(t) :: String.t()

  def name(%__MODULE__{project_module: nil} = project) do
    project
    |> root_path()
    |> Path.split()
    |> List.last()
  end

  def name(%__MODULE__{project_module: project_module}) do
    module_string = to_string(project_module)

    with ["Elixir" | tail] <- String.split(module_string, "."),
         true <- ends_with_mix_project?(tail) do
      tail |> List.delete_at(-1) |> Enum.join(".")
    else
      _ -> module_string
    end
  end

  defp ends_with_mix_project?(module_path) do
    List.last(module_path) == "MixProject"
  end

  @doc """
  Retrieves the name of the project as an atom
  """
  @spec atom_name(t) :: atom
  def atom_name(%__MODULE__{project_module: nil} = project) do
    project
    |> name()
    |> String.to_atom()
  end

  def atom_name(%__MODULE__{} = project) do
    project.project_module
  end

  @doc """
  Returns the full path of the project's root directory
  """
  @spec root_path(t) :: Path.t() | nil
  def root_path(%__MODULE__{root_uri: nil}) do
    nil
  end

  def root_path(%__MODULE__{} = project) do
    Document.Path.from_uri(project.root_uri)
  end

  @spec project_path(t) :: Path.t() | nil
  def project_path(%__MODULE__{root_uri: nil}) do
    nil
  end

  def project_path(%__MODULE__{} = project) do
    Document.Path.from_uri(project.root_uri)
  end

  @doc """
  Returns the full path to the project's mix.exs file
  """
  @spec mix_exs_path(t) :: Path.t() | nil
  def mix_exs_path(%__MODULE__{mix_exs_uri: nil}) do
    nil
  end

  def mix_exs_path(%__MODULE__{mix_exs_uri: mix_exs_uri}) do
    Document.Path.from_uri(mix_exs_uri)
  end

  @spec change_environment_variables(t, map() | nil) ::
          {:ok, t} | error_with_message() | restart_notification()
  def change_environment_variables(%__MODULE__{} = project, environment_variables) do
    set_env_vars(project, environment_variables)
  end

  @doc """
  Returns the full path to the project's lexical workspace directory

  Lexical maintains a workspace directory in project it konws about, and places various
  artifacts there. This function returns the full path to that directory
  """
  @spec workspace_path(t) :: String.t()
  def workspace_path(%__MODULE__{} = project) do
    project
    |> root_path()
    |> Path.join(@workspace_directory_name)
  end

  @doc """
  Returns the full path to a file in lexical's workspace directory
  """
  @spec workspace_path(t, String.t() | [String.t()]) :: String.t()
  def workspace_path(%__MODULE__{} = project, relative_path) when is_binary(relative_path) do
    workspace_path(project, [relative_path])
  end

  def workspace_path(%__MODULE__{} = project, relative_path) when is_list(relative_path) do
    Path.join([workspace_path(project) | relative_path])
  end

  @doc """
  Returns the full path to the directory where lexical puts build artifacts
  """
  def build_path(%__MODULE__{} = project) do
    project
    |> workspace_path()
    |> Path.join("build")
  end

  @doc """
  Creates lexical's workspace directory if it doesn't already exist
  """
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
      |> Document.Path.absolute_from_uri()
      |> Path.expand()

    if File.exists?(root_path) do
      expanded_uri = Document.Path.to_uri(root_path)
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
        | mix_exs_uri: Document.Path.to_uri(possible_mix_exs_path),
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
