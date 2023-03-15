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

  property "clamp works with all integers by simpler property" do
    check all(
            value <- integer(),
            low = value - 1,
            high = value + 1
          ) do
      assert Math.clamp(value, low, high) == value
    end

    check all(
            low <- integer(),
            value = low - 1,
            high = value + 1
          ) do
      assert Math.clamp(value, low, high) == low
    end

    check all(
            high <- integer(),
            low = high - 1,
            value = low - 1
          ) do
      assert Math.clamp(value, low, high) == low
    end
  end

  property "clamp works with all positive_integers" do
    check all(
            low <- positive_integer(),
            value <- integer(0..low),
            high_range = (low + 1)..(low + 1_000_000),
            high <-
              integer(high_range)
          ) do
      assert Math.clamp(value, low, high) == low
    end

    check all(
            value <- positive_integer(),
            low <- integer(0..value),
            high_range = (value + 1)..(value + 1_000_000),
            high <-
              integer(high_range)
          ) do
      assert Math.clamp(value, low, high) == value
    end

    check all(
            high <- positive_integer(),
            low <- integer(0..high),
            value_range = (high + 1)..(high + 1_000_000),
            value <-
              integer(value_range)
          ) do
      assert Math.clamp(value, low, high) == high
    end
  end
end
