defmodule Lexical.Proto.Macros.Typespec do
  def typespec(opts \\ [], env \\ nil)

  def typespec([], _) do
    quote do
      %__MODULE__{}
    end
  end

  def typespec(opts, env) when is_list(opts) do
    typespecs =
      for {name, type} <- opts,
          name != :.. do
        {name, do_typespec(type, env)}
      end

    quote do
      %__MODULE__{unquote_splicing(typespecs)}
    end
  end

  def typespec(typespec, env) do
    quote do
      unquote(do_typespec(typespec, env))
    end
  end

  def choice(options, env) do
    do_typespec({:one_of, [], [options]}, env)
  end

  def keyword_constructor_options(opts, env) do
    for {name, type} <- opts,
        name != :.. do
      {name, do_typespec(type, env)}
    end
    |> or_types()
  end

  defp do_typespec([], _env) do
    # This is what's presented to typespec when a response has no results, as in the Shutdown response
    nil
  end

  defp do_typespec(nil, _env) do
    quote(do: nil)
  end

  defp do_typespec({:boolean, _, _}, _env) do
    quote(do: boolean())
  end

  defp do_typespec({:string, _, _}, _env) do
    quote(do: String.t())
  end

  defp do_typespec({:integer, _, _}, _env) do
    quote(do: integer())
  end

  defp do_typespec({:float, _, _}, _env) do
    quote(do: float())
  end

  defp do_typespec({:__MODULE__, [line: 740], nil}, env) do
    env.module
  end

  defp do_typespec({:optional, _, [optional_type]}, env) do
    quote do
      unquote(do_typespec(optional_type, env)) | nil
    end
  end

  defp do_typespec({:__aliases__, _, raw_alias} = aliased_module, env) do
    expanded_alias = Macro.expand(aliased_module, env)

    case List.last(raw_alias) do
      :Position ->
        other_alias =
          case expanded_alias do
            Lexical.Document.Range ->
              Lexical.Protocol.Types.Range

            _ ->
              Lexical.Document.Range
          end

        quote do
          unquote(expanded_alias).t() | unquote(other_alias).t()
        end

      :Range ->
        other_alias =
          case expanded_alias do
            Lexical.Document.Range ->
              Lexical.Protocol.Types.Range

            _ ->
              Lexical.Document.Range
          end

        quote do
          unquote(expanded_alias).t() | unquote(other_alias).t()
        end

      _ ->
        quote do
          unquote(expanded_alias).t()
        end
    end
  end

  defp do_typespec({:literal, _, value}, _env) when is_atom(value) do
    quote do
      unquote(value)
    end
  end

  defp do_typespec({:literal, _, [value]}, _env) do
    literal_type(value)
  end

  defp do_typespec({:type_alias, _, [alias_dest]}, env) do
    do_typespec(alias_dest, env)
  end

  defp do_typespec({:one_of, _, [type_list]}, env) do
    refined =
      type_list
      |> Enum.map(&do_typespec(&1, env))
      |> or_types()

    quote do
      unquote(refined)
    end
  end

  defp do_typespec({:list_of, _, items}, env) do
    refined =
      items
      |> Enum.map(&do_typespec(&1, env))
      |> or_types()

    quote do
      [unquote(refined)]
    end
  end

  defp do_typespec({:tuple_of, _, [items]}, env) do
    refined = Enum.map(items, &do_typespec(&1, env))

    quote do
      {unquote_splicing(refined)}
    end
  end

  defp do_typespec({:map_of, _, items}, env) do
    value_types =
      items
      |> Enum.map(&do_typespec(&1, env))
      |> or_types()

    quote do
      %{String.t() => unquote(value_types)}
    end
  end

  defp do_typespec({:any, _, _}, _env) do
    quote do
      any()
    end
  end

  defp or_types(list_of_types) do
    Enum.reduce(list_of_types, nil, fn
      type, nil ->
        quote do
          unquote(type)
        end

      type, acc ->
        quote do
          unquote(type) | unquote(acc)
        end
    end)
  end

  defp literal_type(thing) do
    case thing do
      string when is_binary(string) ->
        quote(do: String.t())

      integer when is_integer(integer) ->
        quote(do: integer())

      float when is_binary(float) ->
        quote(do: float())

      boolean when is_boolean(boolean) ->
        quote(do: boolean())

      atom when is_atom(atom) ->
        atom

      [] ->
        quote(do: [])

      [elem | _] ->
        quote(do: [unquote(literal_type(elem))])
    end
  end
end
