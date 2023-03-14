defmodule Lexical.MathTest do
  alias Lexical.Math

  use ExUnit.Case, async: true

  test "Clamp between min and max" do
    assert Math.clamp(43, 0, 42) == 42
    assert Math.clamp(-1, 0, 42) == 0
  end
end
