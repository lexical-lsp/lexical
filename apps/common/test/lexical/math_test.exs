defmodule Lexical.MathTest do
  alias Lexical.Math

  use ExUnit.Case, async: true
  use ExUnitProperties

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

  property "clamp works with all integers" do
    check all(
            ints <- uniq_list_of(integer(), length: 3),
            [low, mid, high] = Enum.sort(ints)
          ) do
      assert Math.clamp(mid, low, high) == mid
      assert Math.clamp(low, mid, high) == mid
      assert Math.clamp(high, low, mid) == mid
    end
  end

  describe "count_leading_space/1" do
    test "returns 0 when string is empty" do
      assert Math.count_leading_spaces("") == 0
    end

    test "returns 0 when string has no leading spaces" do
      assert Math.count_leading_spaces("hello") == 0
    end

    test "returns 2 when string has two leading spaces" do
      assert Math.count_leading_spaces("  hello") == 2
    end

    test "return 1 when string has one leading tab" do
      assert Math.count_leading_spaces("\thello") == 1
    end
  end
end
