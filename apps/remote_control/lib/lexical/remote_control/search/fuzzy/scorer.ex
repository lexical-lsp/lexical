defmodule Lexical.RemoteControl.Search.Fuzzy.Scorer do
  @moduledoc """
  Scores a match based on heuristics.

  The goal of this module is to have a quick to build and fast to query fuzzy matching system.

  Matches match a subject based on a pattern given by the user. A string is considered to match
  if the subject contains all of the pattern's characters, in any order. However, patterns
  can be boosted based on heuristics.

  The heuristics boost:
    1. Larger patterns
    2. Patterns that match more consecutive characters
    3. Patterns that match the beginning of the subject
    4. Patterns that match the case of the subject

  Based loosely on https://medium.com/@Srekel/implementing-a-fuzzy-search-algorithm-for-the-debuginator-cacc349e6c55
  """
  defstruct match?: false,
            index: 0,
            matched_character_positions: []

  import Record

  defrecord :subject, graphemes: nil, normalized: nil

  @typedoc "A match score. Higher numbers mean a more relevant match."
  @type score :: integer
  @type score_result :: {match? :: boolean(), score}
  @type subject :: term()
  @type pattern :: String.t()
  @type preprocessed ::
          record(:subject, graphemes: tuple(), normalized: String.t())
  @non_match_score -5000

  @doc """
  Pre-processes a subject into separate parts that will be helpful during the search phase.
  Pre-processing allows us to do the work of extracting important metadata per-subject
  rather than on every request.
  """
  @spec preprocess(subject()) :: preprocessed()
  def preprocess(subject) when is_binary(subject) do
    graphemes =
      subject
      |> String.graphemes()
      |> List.to_tuple()

    subject(graphemes: graphemes, normalized: normalize(subject))
  end

  def preprocess(subject) do
    subject
    |> inspect()
    |> preprocess()
  end

  @doc """
  Scores the pattern based on the subject

  Returns a two-element tuple, where the first element is a boolean representing if the
  pattern matches the subject. The second element is the score of the match. Higher
  scores mean a better match. Scores can be negative.
  """
  @spec score(subject(), pattern()) :: score_result()
  def score(subject, pattern) when is_binary(subject) do
    subject
    |> preprocess()
    |> score(pattern)
  end

  def score(subject(normalized: normalized) = subject, pattern) do
    normalized_pattern = normalize(pattern)

    case collect_scores(normalized, normalized_pattern) do
      [] ->
        {false, @non_match_score}

      elems ->
        max_score =
          elems
          |> Enum.map(&calculate_score(&1, subject, pattern))
          |> Enum.max()

        {true, max_score}
    end
  end

  defp collect_scores(normalized, normalized_pattern, acc \\ [])

  defp collect_scores(normalized_subject, normalized_pattern, acc) do
    # we collect scores because it's possible that a better match occurs later
    # in the subject, and if we start peeling off characters greedily, we'll miss
    # it. This is more expensive, but it's still pretty quick.

    case do_score(normalized_subject, normalized_pattern, %__MODULE__{}) do
      %__MODULE__{match?: true, matched_character_positions: [pos | _]} = score ->
        subject_substring = String.slice(normalized_subject, (pos + 1)..-1//1)
        collect_scores(subject_substring, normalized_pattern, [score | acc])

      _ ->
        acc
    end
  end

  # out of pattern, we have a match.
  defp do_score(_, <<>>, %__MODULE__{} = score) do
    %__MODULE__{
      score
      | match?: true,
        matched_character_positions: Enum.reverse(score.matched_character_positions)
    }
  end

  # we're out of subject, but we still have pattern, no match
  defp do_score(<<>>, _, %__MODULE__{} = score) do
    %__MODULE__{
      score
      | matched_character_positions: Enum.reverse(score.matched_character_positions)
    }
  end

  defp do_score(
         <<match::utf8, subject_rest::binary>>,
         <<match::utf8, pattern_rest::binary>>,
         %__MODULE__{} = score
       ) do
    score =
      score
      |> add_to_list(:matched_character_positions, score.index)
      |> increment(:index)

    do_score(subject_rest, pattern_rest, score)
  end

  defp do_score(<<_unmatched::utf8, subject_rest::binary>>, pattern, %__MODULE__{} = score) do
    score = increment(score, :index)

    do_score(subject_rest, pattern, score)
  end

  defp increment(%__MODULE__{} = score, field_name) do
    Map.update!(score, field_name, &(&1 + 1))
  end

  defp add_to_list(%__MODULE__{} = score, field_name, value) do
    Map.update(score, field_name, [value], &[value | &1])
  end

  defp calculate_score(%__MODULE__{match?: false}, _, _) do
    @non_match_score
  end

  defp calculate_score(%__MODULE__{} = score, subject() = subject, pattern) do
    pattern_length = String.length(pattern)

    {consecutive_count, consecutive_bonus} =
      consecutive_match_bonus(score.matched_character_positions)

    match_amount_boost = consecutive_count * pattern_length * 10

    [first_match_position | _] = score.matched_character_positions

    pattern_length_boost = pattern_length

    # penalize first matches further in the string by making them negative.
    first_match_bonus = max(0 - first_match_position, 10)

    case_match_boost = case_match_boost(pattern, score.matched_character_positions, subject)

    mismatched_penalty = mismatched_penalty(score.matched_character_positions)

    pattern_length_boost + consecutive_bonus + first_match_bonus + case_match_boost +
      match_amount_boost - mismatched_penalty
  end

  defp normalize(string) do
    String.downcase(string)
  end

  @consecutive_character_bonus 15

  def consecutive_match_bonus(matched_positions) do
    # This function checks for consecutive matched characters, and
    # makes matches with more consecutive matched characters worth more.
    # This means if I type En, it will match Enum more than it will match
    # Something

    max_streak =
      matched_positions
      |> Enum.reduce([[]], fn
        current, [[last | streak] | rest] when last == current - 1 ->
          [[current, last | streak] | rest]

        current, acc ->
          [[current] | acc]
      end)
      |> Enum.max_by(&length/1)

    streak_length = length(max_streak)
    {streak_length, @consecutive_character_bonus * streak_length}
  end

  @mismatched_chracter_penalty 5

  def mismatched_penalty(matched_positions) do
    {penalty, _} =
      matched_positions
      |> Enum.reduce({0, -1}, fn matched_position, {penalty, last_match} ->
        distance = matched_position - last_match
        {penalty + distance * @mismatched_chracter_penalty, matched_position}
      end)

    penalty
  end

  defp case_match_boost(pattern, matched_positions, subject(graphemes: graphemes)) do
    do_case_match_boost(pattern, matched_positions, graphemes, 0)
  end

  # iterate over the matches, find the character in the subject with that index, and compare it
  # to the one in the pattern, boost if they're the same.
  defp do_case_match_boost(_, [], _, boost), do: boost

  defp do_case_match_boost(<<char::utf8, pattern_rest::binary>>, [index | rest], graphemes, boost) do
    boost =
      if grapheme_to_utf8(graphemes, index) == char do
        boost + 1
      else
        boost
      end

    do_case_match_boost(pattern_rest, rest, graphemes, boost)
  end

  defp grapheme_to_utf8(graphemes, position) do
    <<c::utf8>> = elem(graphemes, position)

    c
  end
end
