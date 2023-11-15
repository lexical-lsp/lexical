defmodule Lexical.Ast.Detection.TypeTest do
  alias Lexical.Ast.Detection

  use Lexical.Test.DetectionCase,
    for: Detection.Type,
    assertions: [[:type, :*]]

  test "is not detected if you're in a variable named type" do
    refute_detected ~q[type = 3]
  end

  test "is not detected right after the type ends" do
    refute_detected ~q[
    @type« my_type :: atom»

    ]
  end
end
