defmodule Lexical.RemoteControl.Search.Fuzzy.ScorerTest do
  alias Lexical.RemoteControl.Search.Fuzzy.Scorer

  use ExUnit.Case

  describe "matching" do
    test "fails if one character doesn't appear" do
      assert {false, _} = Scorer.score("Enum", "Enuq")
    end

    test "fails if no characters appear" do
      assert {false, _} = Scorer.score("Enum", "pq")
    end

    test "a match at the beginning of the string is a match" do
      assert {true, _} = Scorer.score("Enum", "En")
    end

    test "a pattern that contains characters in the string is a match" do
      assert {true, _} = Scorer.score("Enumerable", "Eml")
    end

    test "a pattern that contains letters at the start and end is a match" do
      assert {true, _} = Scorer.score("Baz", "bz")
    end

    test "patterns are case insensitive" do
      assert {true, _} = Scorer.score("Enum", "enu")
    end
  end

  defp score_and_sort(subject, patterns) do
    Enum.sort_by(
      patterns,
      fn pattern ->
        {_, score} = Scorer.score(subject, pattern)
        score
      end,
      :desc
    )
  end

  describe "scoring heuristics" do
    test "longer patterns win" do
      assert ~w(Enumerab Enumera Enum E) =
               score_and_sort("Enumerable", ~w(E Enum Enumerab Enumera))
    end

    test "patterns that match the start of a string win" do
      assert ~w(Enum nume era ble) = score_and_sort("Enumerable", ~w(ble era nume Enum))
    end

    test "patterns that match consecutive characters win" do
      assert ~w(Enum erb nml) = score_and_sort("Enumerable", ~w(Enum erb nml))
    end

    test "patterns that match the case of the subject" do
      assert ~w(Enumera enumera eNUmera) =
               score_and_sort("Enumerable", ~w(eNUmera enumera Enumera))
    end
  end
end
