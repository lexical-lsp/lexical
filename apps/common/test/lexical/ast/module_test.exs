defmodule Lexical.Ast.ModuleTest do
  import Lexical.Ast.Module
  use ExUnit.Case, async: true

  describe "safe_split/2" do
    test "splits elixir modules into binaries by default" do
      assert {:elixir, ~w(Lexical Document Store)} == safe_split(Lexical.Document.Store)
    end

    test "splits elixir modules into binaries" do
      assert {:elixir, ~w(Lexical Document Store)} ==
               safe_split(Lexical.Document.Store, as: :binary)

      assert {:elixir, ~w(Lexical Document Store)} ==
               safe_split(Lexical.Document.Store, as: :binaries)
    end

    test "splits elixir modules into atoms" do
      assert {:elixir, ~w(Lexical Document Store)a} ==
               safe_split(Lexical.Document.Store, as: :atom)

      assert {:elixir, ~w(Lexical Document Store)a} ==
               safe_split(Lexical.Document.Store, as: :atoms)
    end

    test "splits erlang modules" do
      assert {:erlang, ["ets"]} = safe_split(:ets)
      assert {:erlang, [:ets]} = safe_split(:ets, as: :atoms)
      assert {:erlang, [:ets]} = safe_split(:ets, as: :atoms)
    end
  end
end
