defmodule Lexical.TestTest do
  use ExUnit.Case
  doctest Lexical.Test

  test "greets the world" do
    assert Lexical.Test.hello() == :world
  end
end
