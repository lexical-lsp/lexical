defmodule Lexical.RemoteControl.ModulesTest do
  alias Lexical.RemoteControl.Modules

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
    test "it places the module as the first argument" do
      assert [GenEvent] =
               Modules.with_prefix("GenEvent", {Kernel, :macro_exported?, [:__using__, 1]})
    end
  end
end
