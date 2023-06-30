# Copied some code from https://github.com/elixir-lang/elixir/blob/44c18a3/lib/elixir/lib/macro.ex#L440
# only copied the `path/2`
import Kernel, except: [to_string: 1]

defmodule Future.Macro do
  @doc """
  Returns the path to the node in `ast` which `fun` returns `true`.

  The path is a list, starting with the node in which `fun` returns
  true, followed by all of its parents.

  Computing the path can be an efficient operation when you want
  to find a particular node in the AST within its context and then
  assert something about it.

  ## Examples

      iex> Macro.path(quote(do: [1, 2, 3]), & &1 == 3)
      [3, [1, 2, 3]]

      iex> Macro.path(quote(do: Foo.bar(3)), & &1 == 3)
      [3, quote(do: Foo.bar(3))]

      iex> Macro.path(quote(do: %{foo: [bar: :baz]}), & &1 == :baz)
      [
        :baz,
        {:bar, :baz},
        [bar: :baz],
        {:foo, [bar: :baz]},
        {:%{}, [], [foo: [bar: :baz]]}
      ]

  """
  @doc since: "1.14.0"
  def path(ast, fun) when is_function(fun, 1) do
    path(ast, [], fun)
  end

  defp path({form, _, args} = ast, acc, fun) when is_atom(form) do
    acc = [ast | acc]

    if fun.(ast) do
      acc
    else
      path_args(args, acc, fun)
    end
  end

  defp path({form, _meta, args} = ast, acc, fun) do
    acc = [ast | acc]

    if fun.(ast) do
      acc
    else
      path(form, acc, fun) || path_args(args, acc, fun)
    end
  end

  defp path({left, right} = ast, acc, fun) do
    acc = [ast | acc]

    if fun.(ast) do
      acc
    else
      path(left, acc, fun) || path(right, acc, fun)
    end
  end

  defp path(list, acc, fun) when is_list(list) do
    acc = [list | acc]

    if fun.(list) do
      acc
    else
      path_list(list, acc, fun)
    end
  end

  defp path(ast, acc, fun) do
    if fun.(ast) do
      [ast | acc]
    end
  end

  defp path_args(atom, _acc, _fun) when is_atom(atom), do: nil
  defp path_args(list, acc, fun) when is_list(list), do: path_list(list, acc, fun)

  defp path_list([], _acc, _fun) do
    nil
  end

  defp path_list([arg | args], acc, fun) do
    path(arg, acc, fun) || path_list(args, acc, fun)
  end
end
