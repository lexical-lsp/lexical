defmodule LibElixirTest do
  use ExUnit.Case
  doctest LibElixir

  test "greets the world" do
    assert LibElixir.hello() == :world
  end
end
