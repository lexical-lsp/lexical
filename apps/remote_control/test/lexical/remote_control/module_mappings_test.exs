defmodule Lexical.RemoteControl.ModuleMappingsTest do
  alias Lexical.RemoteControl.Dispatch
  alias Lexical.RemoteControl.ModuleMappings
  use ExUnit.Case

  setup do
    start_supervised!(Dispatch)
    start_supervised!(ModuleMappings)
    :ok
  end

  def with_a_populated_cache(_) do
    ModuleMappings.update(__MODULE__, __ENV__.file)
    :ok
  end

  describe "modules_in_file/1" do
    test "returns an empty list if the file isn't in the cache" do
      assert ModuleMappings.modules_in_file("/does/not/exist.ex") == []
    end
  end

  describe "basic functions" do
    setup [:with_a_populated_cache]

    test "it allows you to update a module" do
      ModuleMappings.update(__MODULE__, "foo.text")

      assert ModuleMappings.file_for_module(__MODULE__) == "foo.text"
    end

    test "it allows you to get the file of a module" do
      assert ModuleMappings.file_for_module(__MODULE__) == __ENV__.file
    end

    test "it allows you to get the modules defined in a file" do
      assert ModuleMappings.modules_in_file(__ENV__.file) == [__MODULE__]
    end

    test "it allows to get multiple modules defined in a file" do
      assert ModuleMappings.update(FakeModule, __ENV__.file)

      modules_in_test = ModuleMappings.modules_in_file(__ENV__.file)
      assert FakeModule in modules_in_test
      assert __MODULE__ in modules_in_test
    end

    test "it allows for modules to move from one file to another" do
      ModuleMappings.update(__MODULE__, "other_file.exs")

      assert ModuleMappings.file_for_module(__MODULE__) == "other_file.exs"
      assert ModuleMappings.modules_in_file(__ENV__.file) == []
    end
  end
end
