defmodule Lexical.CodeUnit do
  @moduledoc """
  Code unit and offset conversions

  The LSP protocol speaks in positions, which defines where something happens in a document.
  Positions have a start and an end, which are defined as code unit _offsets_ from the beginning
  of a line. this module helps to convert between utf8, which most of the world speaks
  natively, and utf16, which has been forced upon us by microsoft.

  Converting between offsets and code units is 0(n), and allocations only happen if a
  multi-byte character is detected, at which point, only that character is allocated.
  This exploits the fact that most source code consists of ascii characters, with at best,
  sporadic multi-byte characters in it. Thus, the vast majority of documents will not require
  any allocations at all.
  """
  @type utf8_code_unit :: non_neg_integer()
  @type utf16_code_unit :: non_neg_integer()
  @type utf8_offset :: non_neg_integer()
  @type utf16_offset :: non_neg_integer()

  @type error :: {:error, :misaligned} | {:error, :out_of_bounds}

  # public

  @doc """
  Converts a utf8 character offset into a utf16 character offset. This implementation
  clamps the maximum size of an offset so that any initial character position can be
  passed in and the offset returned will reflect the end of the line.
  """
  @spec utf16_offset(String.t(), utf8_offset()) :: utf16_offset()
  def utf16_offset(binary, character_position) do
    do_utf16_offset(binary, character_position, 0)
  end

  @doc """
  Converts a utf16 character offset into a utf8 character offset. This implementation
  clamps the maximum size of an offset so that any initial character position can be
  passed in and the offset returned will reflect the end of the line.
  """
  @spec utf8_offset(String.t(), utf16_offset()) :: utf8_offset()
  def utf8_offset(binary, character_position) do
    do_utf8_offset(binary, character_position, 1)
  end

  @doc """
  Converts a utf16 position into a corresponding utf8 position
  """
  @spec to_utf8(String.t(), utf16_code_unit()) :: {:ok, utf8_code_unit()} | error
  def to_utf8(binary, utf16_unit) do
    do_to_utf8(binary, utf16_unit, 1)
  end

  @doc """
  Converts a utf8 position into a corresponding utf16 position
  """
  @spec to_utf16(String.t(), utf8_code_unit()) :: {:ok, utf16_code_unit()} | error
  def to_utf16(binary, utf16_unit) do
    do_to_utf16(binary, utf16_unit, 0)
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

  defp do_to_utf16(_, 0, utf16_unit) do
    {:ok, utf16_unit}
  end

  defp do_to_utf16(_, utf8_unit, _) when utf8_unit < 0 do
    {:error, :misaligned}
  end

  defp do_to_utf16(<<>>, _remaining, _utf16_unit) do
    {:error, :out_of_bounds}
  end

  defp do_to_utf16(<<c, rest::binary>>, utf8_unit, utf16_unit) when c < 128 do
    do_to_utf16(rest, utf8_unit - 1, utf16_unit + 1)
  end

  defp do_to_utf16(<<c::utf8, rest::binary>>, utf8_unit, utf16_unit) do
    increment = code_unit_size(c, :utf16)
    decrement = code_unit_size(c, :utf8)

    do_to_utf16(rest, utf8_unit - decrement, utf16_unit + increment)
  end

  # UTF-8

  defp do_utf8_offset(_, 0, offset) do
    offset
  end

  defp do_utf8_offset(<<>>, _, offset) do
    # this clause pegs the offset at the end of the string
    # no matter the character index
    offset
  end

  defp do_utf8_offset(<<c, rest::binary>>, remaining, offset) when c < 128 do
    do_utf8_offset(rest, remaining - 1, offset + 1)
  end

  defp do_utf8_offset(<<c::utf8, rest::binary>>, remaining, offset) do
    increment = code_unit_size(c, :utf8)
    decrement = code_unit_size(c, :utf16)
    do_utf8_offset(rest, remaining - decrement, offset + increment)
  end

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
