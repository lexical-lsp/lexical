defmodule Lexical.Ast.Module do
  @moduledoc """
  Module utilities
  """

  @doc """
  Formats a module name as a string.
  """
  @spec name(module() | Macro.t() | String.t()) :: String.t()
  def name([{:__MODULE__, _, _} | rest]) do
    [__MODULE__ | rest]
    |> Module.concat()
    |> name()
  end

  def name(module_name) when is_list(module_name) do
    module_name
    |> Module.concat()
    |> name()
  end

  def name(module_name) when is_binary(module_name) do
    module_name
  end

  def name(module_name) when is_atom(module_name) do
    module_name
    |> inspect()
    |> name()
  end

  @doc """
  local module name is the last part of a module name

  ## Examples:
      iex> local_name('Lexical.Ast.Module')
      "Module"
  """
  def local_name(entity) when is_list(entity) do
    entity
    |> to_string()
    |> local_name()
  end

  def local_name(entity) when is_binary(entity) do
    entity
    |> String.split(".")
    |> List.last()
  end

  @doc """
  Splits a module into is parts, but handles erlang modules

  Module.split will explode violently when called on an erlang module. This
  implementation will tell you which kind of module it has split, and return the
  pieces. You can also use the options to determine if the pieces are returned as
  strings or atoms

  Options:
    `as` :atoms or :binaries. Default is :binary. Determines what type the elements
    of the returned list are.

  Returns:
    A tuple where the first element is either `:elixir` or `:erlang`, which tells you
    the kind of module that has been split. The second element is a list of the
    module's components. Note: Erlang modules will only ever have a single component.
  """
  @type split_opt :: {:as, :binaries | :atoms}
  @type split_opts :: [split_opt()]
  @type split_return :: {:elixir | :erlang, [String.t()] | [atom()]}

  @spec safe_split(module()) :: split_return()
  @spec safe_split(module(), split_opts()) :: split_return()
  def safe_split(module, opts \\ [])

  def safe_split(module, opts) when is_atom(module) do
    string_name = Atom.to_string(module)

    {type, split_module} =
      case String.split(string_name, ".") do
        ["Elixir" | rest] ->
          {:elixir, rest}

        [_erlang_module] = module ->
          {:erlang, module}
      end

    split_module =
      case Keyword.get(opts, :as, :binaries) do
        :binaries ->
          split_module

        :atoms ->
          Enum.map(split_module, &String.to_atom/1)
      end

    {type, split_module}
  end
end
