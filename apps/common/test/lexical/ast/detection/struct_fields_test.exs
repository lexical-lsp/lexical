defmodule Lexical.Ast.Detection.StructFieldsTest do
  alias Lexical.Ast.Detection

  use Lexical.Test.DetectionCase,
    for: Detection.StructFields,
    assertions: [[:struct_fields, :*]],
    variations: [:match, :function_body, :function_arguments, :module],
    skip: [
      [:struct_reference, :*],
      [:struct_field_value, :*]
    ]

  test "is true if the cursor is in current module arguments" do
    assert_detected ~q[%__MODULE__{«»}]
  end

  test "is true even if the value of a struct key is a tuple" do
    assert_detected ~q[%User{«favorite_numbers: {3}»}]
  end

  test "is true even if the cursor is at a nested struct" do
    assert_detected ~q[%User{«address: %Address{}»]
  end

  test "is detected if it spans multiple lines" do
    assert_detected ~q[
      %User{
        «name: »"John"«,
      »}
    ]
  end
end
