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

  property "count_leading_spaces/1" do
    check all(
            maybe_spaces <- string([?\t, ?\s]),
            string_base <- string(:printable),
            maybe_with_leading_spaces = maybe_spaces <> string_base
          ) do
      space_count = byte_size(maybe_spaces)
      assert Math.count_leading_spaces(maybe_with_leading_spaces) == space_count
    end
  end
end
