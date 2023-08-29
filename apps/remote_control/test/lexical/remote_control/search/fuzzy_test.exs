defmodule Lexical.RemoteControl.Search.FuzzyTest do
  alias Lexical.RemoteControl.Search.Fuzzy
  import Lexical.Test.Entry.Builder
  use ExUnit.Case

  setup do
    entries = [
      reference(subject: Enum),
      reference(subject: Foo.Bar),
      reference(subject: Bar.Baz)
    ]

    fuzzy = Fuzzy.new(entries)
    {:ok, fuzzy: fuzzy, entries: entries}
  end

  def lookup(entities, ref) do
    Enum.find(entities, &(&1.ref == ref))
  end

  describe "housekeeping" do
    test "it can add an entry", %{fuzzy: fuzzy} do
      refute Fuzzy.has_subject?(fuzzy, Other)
      entry = reference(subject: Other)

      fuzzy = Fuzzy.add(fuzzy, entry)
      assert Fuzzy.has_subject?(fuzzy, Other)
    end

    test "a refernce can be removed", %{fuzzy: fuzzy, entries: [to_remove | _]} do
      assert Fuzzy.has_subject?(fuzzy, to_remove.subject)
      fuzzy = Fuzzy.drop_refs(fuzzy, [to_remove.ref])

      refute Fuzzy.has_subject?(fuzzy, to_remove.subject)
    end

    test "all references belonging to a path can be removed", %{fuzzy: fuzzy, entries: entries} do
      entry = List.first(entries)
      path_to_remove = entry.path
      assert Enum.all?(entries, &Fuzzy.has_subject?(fuzzy, &1.subject))

      fuzzy = Fuzzy.delete_path(fuzzy, path_to_remove)

      refute Fuzzy.has_path?(fuzzy, path_to_remove)
      refute Enum.any?(entries, &Fuzzy.has_subject?(fuzzy, &1.subject))
    end
  end

  describe "match/2" do
    test "fuzzy searching can find prefixes", %{fuzzy: fuzzy, entries: entries} do
      assert [ref] = Fuzzy.match(fuzzy, "Enum")
      entry = lookup(entries, ref)
      assert entry.subject == Enum
    end

    test "fuzzy matching is applied", %{fuzzy: fuzzy} do
      assert [_, _] = Fuzzy.match(fuzzy, "br")
    end
  end
end
