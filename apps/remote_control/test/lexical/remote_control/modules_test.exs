defmodule Lexical.RemoteControl.ModulesTest do
  alias Lexical.RemoteControl.Modules
  use Modules.Predicate.Syntax

  use ExUnit.Case
  use Lexical.Test.EventualAssertions

  describe "simple prefixes" do
    test "specifying a prefix with a string" do
      found = Modules.with_prefix("En")

      for module <- found,
          string = module |> Module.split() |> Enum.join(".") do
        assert String.starts_with?(string, "En")
      end
    end

    test "specifying a prefix with a module" do
      found = Modules.with_prefix(Enum)

      for module <- found,
          string = module |> Module.split() |> Enum.join(".") do
        assert String.starts_with?(string, "Enum")
      end
    end

    test "new modules are added after expiry" do
      assert [] = Modules.with_prefix(DoesntExistYet)
      Module.create(DoesntExistYet, quote(do: nil), file: "foo.ex")
      assert_eventually [DoesntExistYet] = Modules.with_prefix(DoesntExistYet)
    end

    test "finds unloaded modules" do
      modules = "GenEvent" |> Modules.with_prefix() |> Enum.map(&to_string/1)
      assert "Elixir.GenEvent" in modules
      assert "Elixir.GenEvent.Stream" in modules

      # ensure it loads the module
      assert "GenEvent" |> List.wrap() |> Module.concat() |> Code.ensure_loaded?()
    end

    test "not finding anything" do
      assert [] = Modules.with_prefix("LexicalIsTheBest")
    end
  end

  describe "using predicate descriptors" do
    test "it should place the argument where you specify" do
      assert [module] =
               Modules.with_prefix("GenEvent", {Kernel, :macro_exported?, [:"$1", :__using__, 1]})

      assert to_string(module) == "Elixir.GenEvent"
    end

    test "it should work with the predicate syntax helpers" do
      assert [GenServer] =
               Modules.with_prefix("GenServer", predicate(&macro_exported?(&1, :__using__, 1)))

      assert [GenServer] =
               Modules.with_prefix(
                 "GenServer",
                 predicate(&Kernel.macro_exported?(&1, :__using__, 1))
               )
    end
  end
end
