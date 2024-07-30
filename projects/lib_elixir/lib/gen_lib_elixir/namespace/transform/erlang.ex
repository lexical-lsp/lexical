defmodule LibElixir.Namespace.Transform.Erlang do
  @moduledoc """
  Utilities for reading and writing erlang terms from and to text
  """

  def path_to_term(file_path) do
    with {:ok, [term]} <- :file.consult(file_path) do
      {:ok, term}
    end
  end

  def term_to_string(term) do
    ~c"~p.~n"
    |> :io_lib.format([term])
    |> :lists.flatten()
    |> List.to_string()
  end
end
