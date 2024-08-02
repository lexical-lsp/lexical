defmodule LibElixir.Namespace do
  @moduledoc """
  This task is used after a release is assembled, and investigates the remote_control
  app for its dependencies, at which point it applies transformers to various parts of the
  app.

  Transformers take a path, find their relevant files and apply transforms to them. For example,
  the Beams transformer will find any instances of modules in .beam files, and will apply namepaces
  to them if the module is one of the modules defined in a dependency.

  This task takes a single argument, which is the full path to the release.
  """

  alias LibElixir.Namespace.Transform

  require Logger

  @root_modules_key {__MODULE__, :root_modules}
  @namespaces_key {__MODULE__, :namespaces}

  def apply!(base_directory, elixir_namespace) do
    set_root_modules!(base_directory)
    set_namespaces!(elixir_namespace)

    Transform.Apps.apply_to_all(base_directory)
    Transform.Beams.apply_to_all(base_directory)
    Transform.AppDirectories.apply_to_all(base_directory)

    :ok
  end

  def app_names do
    [:elixir]
  end

  def elixir_root_modules do
    :persistent_term.get(@root_modules_key).elixir
  end

  def erlang_root_modules do
    :persistent_term.get(@root_modules_key).erlang
  end

  def set_root_modules!(base_directory) do
    root_modules =
      base_directory
      |> File.ls!()
      |> Enum.map(fn
        "Elixir." <> elixir_module ->
          [root_module, _] = String.split(elixir_module, ".", parts: 2)
          {:elixir, Module.concat([root_module])}

        erlang_file ->
          {:erlang, erlang_file |> Path.rootname() |> String.to_atom()}
      end)
      |> Enum.uniq()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    special_root_modules = [BitString]
    root_modules = update_in(root_modules.elixir, &(special_root_modules ++ &1))

    :persistent_term.put(@root_modules_key, root_modules)
  end

  def elixir_namespace do
    :persistent_term.get(@namespaces_key).elixir
  end

  def erlang_namespace do
    :persistent_term.get(@namespaces_key).erlang
  end

  def app_name(elixir_namespace) do
    :"#{erlang_namespace_name(elixir_namespace)}elixir"
  end

  def elixir_namespace_name(elixir_namespace) do
    case to_string(elixir_namespace) do
      "Elixir." <> namespace -> "#{namespace}."
      namespace -> "#{namespace}."
    end
  end

  def erlang_namespace_name(elixir_namespace) do
    elixir_namespace
    |> Macro.underscore()
    |> String.replace("/", "_")
    |> then(&(&1 <> "_"))
  end

  def set_namespaces!(elixir_namespace) do
    ex_namespace_string = elixir_namespace_name(elixir_namespace)
    erl_namespace_string = erlang_namespace_name(elixir_namespace)

    :persistent_term.put(@namespaces_key, %{
      elixir: ex_namespace_string,
      erlang: erl_namespace_string
    })
  end
end
