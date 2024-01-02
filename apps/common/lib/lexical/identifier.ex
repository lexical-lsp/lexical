defmodule Lexical.Identifier do
  @doc """
  Returns the next globally unique identifier.
  Raises a MatchError if this cannot be computed.
  """
  def next_global! do
    {:ok, next_id} = Snowflake.next_id()
    next_id
  end
end
