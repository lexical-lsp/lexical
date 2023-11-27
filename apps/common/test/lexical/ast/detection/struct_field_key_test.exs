defmodule Lexical.Ast.Detection.StructFieldKeyTest do
  alias Lexical.Ast.Detection

  use Lexical.Test.DetectionCase,
    for: Detection.StructFieldKey,
    assertions: [[:struct_field_key, :*]],
    skip: [
      [:struct_fields, :*],
      [:struct_reference, :*],
      [:struct_field_value, :*]
    ],
    variations: [:module]

  test "is detected if a key is partially typed" do
    assert_detected ~q[%User{«fo»}]
  end
end
