defmodule Lexical.ProtocolTest do
  use ExUnit.Case
  doctest Lexical.Protocol

  test "greets the world" do
    assert Lexical.Protocol.hello() == :world
  end
end
