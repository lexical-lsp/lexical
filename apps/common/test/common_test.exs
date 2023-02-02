defmodule CommonTest do
  use ExUnit.Case
  doctest Common

  test "greets the world" do
    assert Common.hello() == :world
  end
end
