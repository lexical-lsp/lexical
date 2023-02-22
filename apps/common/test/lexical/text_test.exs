defmodule Lexical.TextTest do
  alias Lexical.Text

  use ExUnit.Case

  describe "stringifying modules" do
    test "it correctly handles a top-level module" do
      assert "Lexical" == Text.module_name(Lexical)
    end

    test "it correctly handles a nested module" do
      assert "Lexical.Text" == Text.module_name(Lexical.Text)
    end

    test "it correctly handles an erlang module name" do
      assert ":ets" == Text.module_name(:ets)
    end
  end

  describe "formatting time" do
    test "it handles milliseconds" do
      assert "1.0 seconds" = Text.format_seconds(1000, unit: :millisecond)
      assert "1.5 seconds" = Text.format_seconds(1500, unit: :millisecond)
    end

    test "microseconds is the default" do
      assert "150 ms" = Text.format_seconds(150_000)
    end

    test "it handles microseconds" do
      assert "2 ms" = Text.format_seconds(2000)
      assert "0.2 ms" = Text.format_seconds(200)
      assert "0.02 ms" = Text.format_seconds(20)
    end
  end
end
