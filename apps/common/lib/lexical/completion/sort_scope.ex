defmodule Lexical.Completion.SortScope do
  def variable(deprecated \\ false)
  def variable(false), do: "000"
  def variable(true), do: "001"

  def local(deprecated \\ false)
  def local(false), do: "010"
  def local(true), do: "011"

  def remote(deprecated \\ false)
  def remote(false), do: "100"
  def remote(true), do: "101"

  def global(deprecated \\ false)
  def global(false), do: "110"
  def global(true), do: "111"

  def auto(deprecated \\ false)
  def auto(false), do: "200"
  def auto_declarations(true), do: "201"

  def default(deprecated \\ false)
  def default(false), do: "990"
  def default(true), do: "991"
end