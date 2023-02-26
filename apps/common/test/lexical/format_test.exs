defmodule Lexical.FormatTest do
  alias Lexical.Format

  use ExUnit.Case

  describe "stringifying modules" do
    test "it correctly handles a top-level module" do
      assert "Lexical" == Format.module(Lexical)
    end

    test "it correctly handles a nested module" do
      assert "Lexical.Text" == Format.module(Lexical.Text)
    end

    test "it correctly handles an erlang module name" do
      assert ":ets" == Format.module(:ets)
    end
  end

  describe "formatting time" do
    test "it handles milliseconds" do
      assert "1.0 seconds" = Format.time(1000, unit: :millisecond)
      assert "1.5 seconds" = Format.time(1500, unit: :millisecond)
    end

    test "microseconds is the default" do
      assert "150 ms" = Format.time(150_000)
    end

    test "it handles microseconds" do
      assert "2 ms" = Format.time(2000)
      assert "0.2 ms" = Format.time(200)
      assert "0.02 ms" = Format.time(20)
    end
  end
end
