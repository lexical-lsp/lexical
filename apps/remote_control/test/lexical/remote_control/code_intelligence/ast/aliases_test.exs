defmodule Lexical.RemoteControl.CodeIntelligence.Ast.AliasesTest do
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.RemoteControl.CodeIntelligence.Ast

  import Lexical.Test.CursorSupport
  import Lexical.Test.CodeSigil

  use ExUnit.Case, async: true

  describe "at_position/2" do
    test "returns mapping when there are modules has been alised" do
      source = ~q[
        defmodule MyModule do
          alias Project.Structs.User|
        end
      ]

      aliases = at_position(source)

      assert aliases[MyModule] == MyModule
      assert aliases[User] == Project.Structs.User
      assert aliases[:__MODULE__] == MyModule
    end

    test "returns mapping when there are modules has been alised with as" do
      source = ~q[
        defmodule MyModule do
          alias Project.Structs.User, as: MyUser|
        end
      ]

      aliases = at_position(source)

      assert aliases[MyModule] == MyModule
      assert aliases[MyUser] == Project.Structs.User
      assert aliases[:__MODULE__] == MyModule
    end

    test "returns mapping when there is alias not expanded" do
      source = ~q[
        defmodule MyModule do
          alias Project.Child.{Struct1, Struct2}
          alias Struct2.User, as: MyUser|
        end
      ]
      aliases = at_position(source)

      assert aliases[MyModule] == MyModule
      assert aliases[Struct1] == Project.Child.Struct1
      assert aliases[Struct2] == Project.Child.Struct2
      assert aliases[MyUser] == Project.Child.Struct2.User
      assert aliases[:__MODULE__] == MyModule
    end

    test "returns mapping when there are nested modules" do
      source = ~q(
        defmodule Project.MyModule do
          defmodule Child do
            defmodule GrandChild do
              defstruct [:field1, :field2]|
            end
          end
        end
      )

      aliases = at_position(source)

      assert aliases[Project.MyModule] == Project.MyModule
      assert aliases[Child] == Project.MyModule.Child
      assert aliases[GrandChild] == Project.MyModule.Child.GrandChild
      assert aliases[:__MODULE__] == Project.MyModule.Child.GrandChild
    end

    test "returns mapping even there is implicit alias" do
      source = ~q<
        defmodule Server do
          defmodule State do
            defstruct [:status]
          end

          def init do
            %State{|}
          end
        end
      >

      aliases = at_position(source)

      assert aliases[Server] == Server
      assert aliases[State] == Server.State
      assert aliases[:__MODULE__] == Server
    end

    test "returns mapping even alias the child of current module" do
      source = ~q<
        defmodule MyModule do
          defmodule Child do
            defstruct [:status]
          end

          alias __MODULE__.Child, as: MyChild

          %MyChild{|}
        end
      >

      aliases = at_position(source)

      assert aliases[MyModule] == MyModule
      assert aliases[Child] == MyModule.Child
      assert aliases[MyChild] == MyModule.Child
      assert aliases[:__MODULE__] == MyModule
    end

    test "returns mapping even alias the child of current module and not be expanded" do
      source = ~q<
        defmodule Project.MyModule do
          alias __MODULE__.{Child, Other}|
        end
      >

      aliases = at_position(source)

      assert aliases[Project.MyModule] == Project.MyModule
      assert aliases[Child] == Project.MyModule.Child
      assert aliases[Other] == Project.MyModule.Other
      assert aliases[:__MODULE__] == Project.MyModule
    end
  end

  defp at_position(source) do
    Ast.Aliases.at_position(document(source), position(source))
  end

  defp document(source) do
    text = strip_cursor(source)
    Document.new(file_uri(), text, 1)
  end

  defp file_uri do
    "file:///elixir.ex"
  end

  defp position(source) do
    {line, column} = cursor_position(source)
    Position.new(line, column)
  end
end
