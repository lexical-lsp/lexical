defmodule ProtoTest do
  use ExUnit.Case
  doctest Proto

  test "greets the world" do
    assert Proto.hello() == :world
  end
end
