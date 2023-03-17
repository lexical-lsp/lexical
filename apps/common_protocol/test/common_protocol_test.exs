defmodule CommonProtocolTest do
  use ExUnit.Case
  doctest CommonProtocol

  test "greets the world" do
    assert CommonProtocol.hello() == :world
  end
end
