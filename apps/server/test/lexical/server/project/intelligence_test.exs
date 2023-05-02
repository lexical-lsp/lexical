defmodule Lexical.Server.Project.IntelligenceTest do
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.Server.Project.Dispatch
  alias Lexical.Server.Project.Intelligence
  alias Lexical.Test.Fixtures

  use ExUnit.Case
  import Messages

  setup do
    project = Fixtures.project()
    {:ok, _dispatch} = start_supervised({Dispatch, project})
    {:ok, _intelligence} = start_supervised({Intelligence, project})

    {:ok, project: project}
  end

  def with_parent_and_children(%{project: project}) do
    [
      module_updated(name: "Parent", functions: []),
      module_updated(name: "Parent.Child"),
      module_updated(name: "Parent.ChildWithStruct", struct: [name: nil, value: nil]),
      module_updated(name: "Parent.Child.Grandchild"),
      module_updated(name: "Parent.Child.GrandchildWithStruct", struct: [name: nil])
    ]
    |> Enum.each(&Dispatch.broadcast(project, &1))

    Process.sleep(50)
    :ok
  end

  describe "child_defines_struct?/2" do
    setup [:with_parent_and_children]

    test "returns true if a child defines a struct", %{project: project} do
      assert Intelligence.child_defines_struct?(project, "Parent")
      assert Intelligence.child_defines_struct?(project, "Parent.Child")

      assert Intelligence.child_defines_struct?(project, Parent)
      assert Intelligence.child_defines_struct?(project, Parent.Child)
    end

    test "returns false if a child doesn't define a struct", %{project: project} do
      refute Intelligence.child_defines_struct?(project, "Parent.Child.Grandchild")
      refute Intelligence.child_defines_struct?(project, Parent.Child.Grandchild)
    end
  end

  describe "child_struct_modules/2" do
    setup [:with_parent_and_children]

    test "should only return direct children of a given module", %{project: project} do
      assert ["Parent.ChildWithStruct"] = Intelligence.child_struct_modules(project, "Parent")

      assert ["Parent.Child.GrandchildWithStruct"] =
               Intelligence.child_struct_modules(project, Parent.Child)
    end
  end
end
