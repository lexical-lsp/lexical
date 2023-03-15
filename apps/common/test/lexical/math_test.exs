defmodule Lexical.MathTest do
  alias Lexical.Math

  use ExUnit.Case, async: true

  describe "clamp/3" do
    test "returns low when value is less than low" do
      assert Math.clamp(-5, 0, 5) == 0
    end

    test "returns value when value is between low and high" do
      assert Math.clamp(3, 0, 5) == 3
    end

    test "returns high when value is greater than high" do
      assert Math.clamp(6, 0, 5) == 5
    end
  end
end
