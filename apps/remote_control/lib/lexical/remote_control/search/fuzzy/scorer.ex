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

  defrecord :subject, original: nil, graphemes: nil, normalized: nil

  @typedoc "A match score. Higher numbers mean a more relevant match."
  @type score :: integer
  @type score_result :: {match? :: boolean(), score}
  @type subject :: term()
  @type pattern :: String.t()
  @type preprocessed ::
          record(:subject, original: String.t(), graphemes: tuple(), normalized: String.t())
  @non_match_score -500

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

    subject(original: subject, graphemes: graphemes, normalized: normalize(subject))
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
    %__MODULE__{} = score = do_score(normalized, normalize(pattern), %__MODULE__{})

    score = %__MODULE__{
      score
      | matched_character_positions: Enum.reverse(score.matched_character_positions)
    }

    {score.match?, calculate_score(score, subject, pattern)}
  end

  # out of pattern, we have a match.
  defp do_score(_, <<>>, %__MODULE__{} = score) do
    %__MODULE__{score | match?: true}
  end

  # we're out of subject, but we still have pattern, no match
  defp do_score(<<>>, _, %__MODULE__{} = score) do
    score
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
    Map.update(score, field_name, 1, &(&1 + 1))
  end

  defp add_to_list(%__MODULE__{} = score, field_name, value) do
    Map.update(score, field_name, [value], &[value | &1])
  end

  defp calculate_score(%__MODULE__{match?: false}, _, _) do
    @non_match_score
  end

  defp calculate_score(%__MODULE__{} = score, subject() = subject, pattern) do
    subject(graphemes: graphemes) = subject
    match_amount_boost = 0 - (tuple_size(graphemes) - length(score.matched_character_positions))

    [first_match_position | _] = score.matched_character_positions

    pattern_length_boost = String.length(pattern)

    consecutive_bonus = consecutive_match_bonus(score.matched_character_positions)

    # penalize first matches further in the string by making them negative.
    first_match_bonus = 0 - first_match_position

    case_match_boost = case_match_boost(score.matched_character_positions, pattern, subject)

    pattern_length_boost + consecutive_bonus + first_match_bonus + case_match_boost +
      match_amount_boost
  end

  defp normalize(string) do
    String.downcase(string)
  end

  @consecutive_character_bonus 5

  defp consecutive_match_bonus(matched_positions) do
    # This function checks for consecutive matched characters, and
    # makes matches with more consecutive matched characters worth more.
    # This means if I type En, it will match Enum more than it will match
    # Something

    [-50 | matched_positions]
    |> Enum.chunk_every(2, 1, [-1])
    |> Enum.reduce(0, fn
      [last, current], acc when current == last + 1 ->
        acc + @consecutive_character_bonus

      _, acc ->
        acc
    end)
  end

  defp case_match_boost(matched_positions, pattern, subject(graphemes: graphemes)) do
    do_case_match_boost(matched_positions, pattern, graphemes, 0)
  end

  # iterate over the matches, find the character in the subject with that index, and compare it
  # to the one in the pattern, boost if they're the same.
  defp do_case_match_boost([], _, _, boost), do: boost

  defp do_case_match_boost([index | rest], <<char::utf8, pattern_rest::binary>>, graphemes, boost) do
    boost =
      if grapheme_to_utf8(graphemes, index) == char do
        boost + 1
      else
        boost
      end

    do_case_match_boost(rest, pattern_rest, graphemes, boost)
  end

  defp do_case_match_boost(matched_positions, <<_::utf8, rest::binary>>, graphemes, boost) do
    do_case_match_boost(matched_positions, rest, graphemes, boost)
  end

  defp grapheme_to_utf8(graphemes, position) do
    <<c::utf8>> = elem(graphemes, position)

    c
  end
end
