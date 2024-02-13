defmodule Lexical.Identifier do
  @doc """
  Returns the next globally unique identifier.
  Raises a MatchError if this cannot be computed.
  """
  def next_global! do
    {:ok, next_id} = Snowflake.next_id()
    next_id
  end

  def to_unix(id) do
    Snowflake.Util.real_timestamp_of_id(id)
  end

  def to_datetime(id) do
    id
    |> to_unix()
    |> DateTime.from_unix!(:millisecond)
  end

  def to_erl(id) do
    %DateTime{year: year, month: month, day: day, hour: hour, minute: minute, second: second} =
      to_datetime(id)

    {{year, month, day}, {hour, minute, second}}
  end
end
