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

    fuzzy = Fuzzy.from_entries(entries)
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

    test "a value can be removed", %{fuzzy: fuzzy, entries: [to_remove | _]} do
      assert Fuzzy.has_subject?(fuzzy, to_remove.subject)
      fuzzy = Fuzzy.drop_values(fuzzy, [to_remove.ref])

      refute Fuzzy.has_subject?(fuzzy, to_remove.subject)
    end

    test "removing a non-existent value is a no-op", %{fuzzy: fuzzy} do
      assert fuzzy == Fuzzy.drop_values(fuzzy, [:does, :not, :exist])
    end

    test "deleting a non-existent key is a no-op", %{fuzzy: fuzzy} do
      assert fuzzy == Fuzzy.delete_key(fuzzy, "does not exist")
    end

    test "all references belonging to a path can be removed", %{fuzzy: fuzzy, entries: entries} do
      entry = List.first(entries)
      path_to_remove = entry.path
      assert Enum.all?(entries, &Fuzzy.has_subject?(fuzzy, &1.subject))

      fuzzy = Fuzzy.delete_key(fuzzy, path_to_remove)

      refute Fuzzy.has_key?(fuzzy, path_to_remove)
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

    test "ordering" do
      entries = [
        reference(ref: 1, subject: ZZZZZZZZZZZZZZZZZZZZZZZZ.ABCD),
        reference(ref: 2, subject: ZZZZA.ZZZZZb.ZZZZc.ZZZZd),
        reference(ref: 3, subject: A.B.C.D),
        reference(ref: 4, subject: Abcd)
      ]

      fuzzy = Fuzzy.from_entries(entries)
      results = Fuzzy.match(fuzzy, "abcd")

      assert results == [4, 3, 2, 1]
    end
  end
end
