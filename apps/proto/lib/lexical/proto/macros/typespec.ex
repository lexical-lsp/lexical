defmodule Lexical.Proto.Macros.Typespec do
  def t(opts \\ [], env \\ nil)

  def t([], _) do
    quote do
      %__MODULE__{}
    end
  end

  def t(opts, env) when is_list(opts) do
    typespecs =
      for {name, type} <- opts,
          name != :.. do
        {name, typespec(type, env)}
      end

    quote do
      %__MODULE__{unquote_splicing(typespecs)}
    end
  end

  def t(typespec, env) do
    quote do
      unquote(typespec(typespec, env))
    end
  end

  def choice(options, env) do
    typespec({:one_of, [], [options]}, env)
  end

  def keyword_constructor_options(opts, env) do
    for {name, type} <- opts,
        name != :.. do
      {name, typespec(type, env)}
    end
    |> or_types()
  end

  defp typespec([], _env) do
    # This is what's presented to typespec when a response has no results, as in the Shutdown response
    nil
  end

  defp typespec(nil, _env) do
    quote(do: nil)
  end

  defp typespec({:boolean, _, _}, _env) do
    quote(do: boolean())
  end

  defp typespec({:string, _, _}, _env) do
    quote(do: String.t())
  end

  defp typespec({:integer, _, _}, _env) do
    quote(do: integer())
  end

  defp typespec({:float, _, _}, _env) do
    quote(do: float())
  end

  defp typespec({:optional, _, [optional_type]}, env) do
    quote do
      unquote(typespec(optional_type, env)) | nil
    end
  end

  defp typespec({:__aliases__, _, raw_alias} = aliased_module, env) do
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

  defp typespec({:literal, _, [value]}, _env) when is_binary(value) do
    quote(do: String.t())
  end

  defp typespec({:literal, _, value}, _env) when is_atom(value) do
    quote do
      unquote(value)
    end
  end

  defp typespec({:one_of, _, [type_list]}, env) do
    refined =
      type_list
      |> Enum.map(&typespec(&1, env))
      |> or_types()

    quote do
      unquote(refined)
    end
  end

  defp typespec({:list_of, _, items}, env) do
    refined =
      items
      |> Enum.map(&typespec(&1, env))
      |> or_types()

    quote do
      [unquote(refined)]
    end
  end

  defp typespec({:map_of, _, items}, env) do
    value_types =
      items
      |> Enum.map(&typespec(&1, env))
      |> or_types()

    quote do
      %{String.t() => unquote(value_types)}
    end
  end

  defp typespec({:any, _, _}, _env) do
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
end
