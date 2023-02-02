defmodule Lexical.Project do
  @moduledoc """
  The representation of the current state of an elixir project.

  This struct contains all the information required to build a project and interrogate its configuration,
  as well as business logic for how to change its attributes.
  """
  alias Lexical.SourceFile
  alias Lexical.LanguageServer

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

  @spec change_mix_env(t, String.t() | nil) ::
          {:ok, t} | error_with_message() | restart_notification()
  def change_mix_env(%__MODULE__{} = project, mix_env) do
    set_mix_env(project, mix_env)
  end

  @spec change_mix_target(t, String.t() | nil) ::
          {:ok, t} | error_with_message() | restart_notification()
  def change_mix_target(%__MODULE__{} = project, mix_target) do
    set_mix_target(project, mix_target)
  end

  @spec change_project_directory(t, String.t() | nil) ::
          {:ok, t} | error_with_message() | restart_notification()
  def change_project_directory(%__MODULE__{} = project, project_directory) do
    set_working_uri(project, project_directory)
  end

  @spec change_environment_variables(t, map() | nil) ::
          {:ok, t} | error_with_message() | restart_notification()
  def change_environment_variables(%__MODULE__{} = project, environment_variables) do
    set_env_vars(project, environment_variables)
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

    if File.exists?(possible_mix_exs_path) do
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
  defp set_working_uri(%__MODULE__{root_uri: root_uri} = old_project, project_directory)
       when is_binary(root_uri) and project_directory != "" do
    # root_path = SourceFile.Path.absolute_from_uri(root_uri)

    # normalized_project_dir =
    #   if is_binary(project_directory) and project_directory != "" do
    #     root_path
    #     |> Path.join(project_directory)
    #     |> Path.expand(root_path)
    #     |> Path.absname()
    #   else
    #     root_path
    #   end

    # cond do
    #   not File.dir?(normalized_project_dir) ->
    #     {:error, "Project directory #{normalized_project_dir} does not exist"}

    #   not subdirectory?(root_path, normalized_project_dir) ->
    #     message =
    #       "Project directory '#{normalized_project_dir}' is not a subdirectory of '#{root_path}'"

    #     {:error, message}

    #   is_nil(old_project.working_uri) and subdirectory?(root_path, normalized_project_dir) ->
    #     :ok = File.cd(normalized_project_dir)

    #     mix_exs_path = find_mix_exs_path(normalized_project_dir)
    #     mix_project? = mix_exs_exists?(mix_exs_path)

    #     mix_exs_uri =
    #       if mix_project? do
    #         SourceFile.Path.to_uri(mix_exs_path)
    #       else
    #         nil
    #       end

    #     working_uri = SourceFile.Path.to_uri(normalized_project_dir)

    #     new_project = %__MODULE__{
    #       old_project
    #       | working_uri: working_uri,
    #         mix_project?: mix_project?,
    #         mix_exs_uri: mix_exs_uri
    #     }

    #     {:ok, new_project}

    #   project_path(old_project) != normalized_project_dir ->
    #     {:restart, :warning, "Project directory change detected. Lexical will restart"}

    #   true ->
    #     {:ok, old_project}
    # end
  end

  defp set_working_uri(%__MODULE__{} = old_project, _) do
    {:ok, old_project}
  end

  # Mix env

  defp set_mix_env(%__MODULE__{mix_env: old_env} = old_project, new_env)
       when is_binary(new_env) and new_env != "" do
    case {old_env, String.to_existing_atom(new_env)} do
      {nil, nil} ->
        do_set_mix_env(:test)
        {:ok, %__MODULE__{old_project | mix_env: :test}}

      {nil, new_env} ->
        do_set_mix_env(new_env)
        {:ok, %__MODULE__{old_project | mix_env: new_env}}

      {same, same} ->
        {:ok, old_project}

      _ ->
        {:restart, :warning, "Mix env change detected. Lexical will restart."}
    end
  end

  defp set_mix_env(%__MODULE__{mix_env: nil} = project, _) do
    do_set_mix_env(:test)

    {:ok, %__MODULE__{project | mix_env: :test}}
  end

  defp set_mix_env(%__MODULE__{} = project, _) do
    {:ok, project}
  end

  # Mix target
  defp set_mix_target(%__MODULE__{} = old_project, new_target)
       when is_binary(new_target) and new_target != "" do
    case {old_project.mix_target, String.to_atom(new_target)} do
      {nil, new_target} ->
        do_set_mix_target(new_target)
        {:ok, %__MODULE__{old_project | mix_target: new_target}}

      {same, same} ->
        {:ok, old_project}

      _ ->
        {:restart, :warning, "Mix target change detected. Lexical will restart"}
    end
  end

  defp set_mix_target(%__MODULE__{} = old_project, _) do
    {:ok, old_project}
  end

  defp do_set_mix_env(new_env) do
    if Code.ensure_loaded?(Mix) do
      # Mix.env(new_env)
    end
  end

  defp do_set_mix_target(new_mix_target) do
    if Code.ensure_loaded?(Mix) do
      # Mix.target(new_mix_target)
    end
  end

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

  defp subdirectory?(parent, possible_child) do
    parent_path = Path.expand(parent)
    child_path = Path.expand(possible_child, parent)

    String.starts_with?(child_path, parent_path)
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
