defmodule Lexical.CodeUnit do
  @moduledoc """
  Code unit and offset conversions.

  LSP positions are encoded as UTF-16 code unit offsets from the beginning of a line,
  while positions in Elixir are UTF-8 character positions (graphemes). This module
  deals with converting between the two.
  """

  @type utf8_character_position :: non_neg_integer()
  @type utf8_code_unit_offset :: non_neg_integer()
  @type utf16_code_unit_offset :: non_neg_integer()

  @type error :: {:error, :misaligned} | {:error, :out_of_bounds}

  @doc """
  Converts a 0-based UTF-8 character position to a UTF-16 code unit offset.
  """
  @spec utf8_char_to_utf16_offset(String.t(), utf8_character_position()) ::
          utf16_code_unit_offset()
  def utf8_char_to_utf16_offset(binary, character_position) do
    do_utf16_offset(binary, character_position, 0)
  end

  @doc """
  Converts a 0-based UTF-16 code unit offset to a UTF-8 code unit offset.
  """
  @spec utf16_offset_to_utf8_offset(String.t(), utf16_code_unit_offset()) ::
          {:ok, utf8_code_unit_offset()} | error
  def utf16_offset_to_utf8_offset(binary, utf16_unit) do
    do_to_utf8(binary, utf16_unit, 1)
  end

  @doc """
  Counts the number of utf16 code units in the binary
  """
  @spec count(:utf16 | :utf8, binary()) :: non_neg_integer
  def count(:utf16, binary) do
    do_count_utf16(binary, 0)
  end

  def count(:utf8, binary) do
    do_count_utf8(binary, 0)
  end

  # Private

  # UTF-16

  defp do_count_utf16(<<>>, count) do
    count
  end

  defp do_count_utf16(<<c, rest::binary>>, count) when c < 128 do
    do_count_utf16(rest, count + 1)
  end

  defp do_count_utf16(<<c::utf8, rest::binary>>, count) do
    do_count_utf16(rest, count + code_unit_size(c, :utf16))
  end

  defp do_count_utf8(<<>>, count) do
    count
  end

  defp do_count_utf8(<<c, rest::binary>>, count) when c < 128 do
    do_count_utf8(rest, count + 1)
  end

  defp do_count_utf8(<<c::utf8, rest::binary>>, count) do
    increment = code_unit_size(c, :utf8)
    do_count_utf8(rest, count + increment)
  end

  defp do_utf16_offset(_, 0, offset) do
    offset
  end

  defp do_utf16_offset(<<>>, _, offset) do
    # this clause pegs the offset at the end of the string
    # no matter the character index
    offset
  end

  defp do_utf16_offset(<<c, rest::binary>>, remaining, offset) when c < 128 do
    do_utf16_offset(rest, remaining - 1, offset + 1)
  end

  defp do_utf16_offset(<<c::utf8, rest::binary>>, remaining, offset) do
    increment = code_unit_size(c, :utf16)
    do_utf16_offset(rest, remaining - 1, offset + increment)
  end

  # UTF-8

  defp do_to_utf8(_, 0, utf8_unit) do
    {:ok, utf8_unit}
  end

  defp do_to_utf8(_, utf_16_units, _) when utf_16_units < 0 do
    {:error, :misaligned}
  end

  defp do_to_utf8(<<>>, _remaining, _utf8_unit) do
    {:error, :out_of_bounds}
  end

  defp do_to_utf8(<<c, rest::binary>>, utf16_unit, utf8_unit) when c < 128 do
    do_to_utf8(rest, utf16_unit - 1, utf8_unit + 1)
  end

  defp do_to_utf8(<<c::utf8, rest::binary>>, utf16_unit, utf8_unit) do
    utf8_code_units = code_unit_size(c, :utf8)
    utf16_code_units = code_unit_size(c, :utf16)

    do_to_utf8(rest, utf16_unit - utf16_code_units, utf8_unit + utf8_code_units)
  end

  @unicode_range 0..0x10_FFFF

  defp code_unit_size(c, :utf16) when c in @unicode_range do
    case c do
      c when c in 0x0000..0xFFFF ->
        1

      _ ->
        2
    end
  end

  defp code_unit_size(c, :utf8) when c in @unicode_range do
    # See table at https://en.wikipedia.org/wiki/UTF-8#Encoding
    cond do
      c in 0x00..0x7F -> 1
      c in 0x80..0x7FF -> 2
      c in 0x800..0xFFFF -> 3
      c in 0x1_0000..0x10_FFFF -> 4
    end
  end
end
