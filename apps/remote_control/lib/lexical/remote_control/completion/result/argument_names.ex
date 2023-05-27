defmodule Lexical.RemoteControl.Completion.Result.ArgumentNames do
  @moduledoc """
  Elixir sense, for whatever reason returns all the argument names when asked to do a completion on a function.
  This means that the arity of the function might differ from the argument names returned. Furthermore, the
  argument names have the defaults in them for some reason, which is completely unhelpful for completions.

  The functions below match the arity of the argument names to the given arity, and strip out the defaults,
  rendering the results useful for completion.
  """
  @type argument_names :: [String.t()]
  @default_specifier ~S(\\)

  @spec from_elixir_sense_map(map()) :: :error | argument_names()
  def from_elixir_sense_map(%{args_list: argument_names, arity: arity}) do
    from_elixir_sense(argument_names, arity)
  end

  def from_elixir_sense_map(%{}) do
    :error
  end

  @spec from_elixir_sense([String.t()], non_neg_integer) :: :error | argument_names()
  def from_elixir_sense(argument_names, arity) when is_list(argument_names) do
    {names, required_count} = preprocess(argument_names)

    cond do
      length(argument_names) < arity ->
        :error

      arity < required_count ->
        :error

      true ->
        generate_argument_list(names, required_count, arity)
    end
  end

  defp generate_argument_list(names, required_count, arity) do
    optional_count = arity - required_count

    {arg_list, _} =
      Enum.reduce(names, {[], optional_count}, fn
        {:required, arg_name}, {arg_list, optional_count} ->
          {[arg_name | arg_list], optional_count}

        {:optional, _}, {_arg_list, 0} = acc ->
          acc

        {:optional, arg_name}, {arg_list, optional_count} ->
          {[arg_name | arg_list], optional_count - 1}
      end)

    Enum.reverse(arg_list)
  end

  defp split_on_default(argument) do
    argument
    |> String.split(@default_specifier)
    |> Enum.map(&String.trim/1)
  end

  @spec preprocess(argument_names()) :: {[String.t()], non_neg_integer()}
  defp preprocess(argument_names) do
    {names, required_count} =
      Enum.reduce(argument_names, {[], 0}, fn argument, {names, required_count} ->
        {name, increment} =
          case split_on_default(argument) do
            [argument_name] ->
              {{:required, argument_name}, 1}

            [argument_name, _default] ->
              {{:optional, argument_name}, 0}
          end

        {[name | names], required_count + increment}
      end)

    {Enum.reverse(names), required_count}
  end
end
