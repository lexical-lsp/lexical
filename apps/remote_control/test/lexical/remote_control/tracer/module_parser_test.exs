defmodule Lexical.RemoteControl.Tracer.ModuleParserTest do
  alias Lexical.RemoteControl.Tracer.ModuleParser

  use ExUnit.Case, async: true

  describe "modules at cursor" do
    test "handles single module" do
      assert ModuleParser.modules_at_cursor("  alias MyModule", 9) == ["MyModule"]
    end

    test "handles middle module in module path" do
      assert ModuleParser.modules_at_cursor("  alias MyModule.SubModule.SubSubModule", 26) == [
               "MyModule",
               ".",
               "SubModule"
             ]
    end

    test "handles last module in module path" do
      assert ModuleParser.modules_at_cursor("  alias MyModule.SubModule.SubSubModule", 28) == [
               "MyModule",
               ".",
               "SubModule",
               ".",
               "SubSubModule"
             ]
    end

    test "handles ased module" do
      assert ModuleParser.modules_at_cursor(
               "  alias MyModule.SubModule.SubSubModule, as: MyModule",
               46
             ) == [
               "MyModule",
               ".",
               "SubModule",
               ".",
               "SubSubModule"
             ]
    end
  end

  describe "parse alias modules not expanded" do
    test "handles single child" do
      assert ModuleParser.modules_at_cursor("  alias MyModule.{Child}", 19) == [
               "MyModule",
               ".",
               "Child"
             ]
    end

    test "handles multiple children" do
      assert ModuleParser.modules_at_cursor("  alias MyModule.{Child1, Child2}", 24) == [
               "MyModule",
               ".",
               "Child1"
             ]

      assert ModuleParser.modules_at_cursor("  alias MyModule.{Child1, Child2}", 27) == [
               "MyModule",
               ".",
               "Child2"
             ]
    end

    test "can find parent modules" do
      assert ModuleParser.modules_at_cursor("  alias MyModule.Parent.{}", 18) == [
               "MyModule",
               ".",
               "Parent"
             ]
    end

    test "reutrn empty list when cursor at splition" do
      assert ModuleParser.modules_at_cursor("  alias MyModule.{Child1, Child2}", 25) == []
    end
  end

  describe "modules_at_cursor when referenced" do
    test "handles a single struct referenced" do
      line_text = "  s = %Struct{}"
      assert ModuleParser.modules_at_cursor(line_text, 8) == ["Struct"]
    end

    test "handles the child struct" do
      line_text = "  s = %MyModule.Struct{}"
      assert ModuleParser.modules_at_cursor(line_text, 17) == ["MyModule", ".", "Struct"]
    end

    test "handles func referenced with single module" do
      line_text = "  MyModule.func()"
      assert ModuleParser.modules_at_cursor(line_text, 3) == ["MyModule"]
      assert ModuleParser.modules_at_cursor(line_text, 10) == ["MyModule"]
    end

    test "handles func referenced with a module path" do
      line_text = "  MyModule.SubModule.func()"
      assert ModuleParser.modules_at_cursor(line_text, 12) == ["MyModule", ".", "SubModule"]
    end
  end
end
