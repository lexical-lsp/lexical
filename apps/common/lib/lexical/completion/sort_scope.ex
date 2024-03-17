defmodule Lexical.Completion.SortScope do
  @moduledoc """
  Enumerated categories for sorting completion items.
  """

  def variable(deprecated \\ false)
  def variable(false), do: "00"
  def variable(true), do: "01"

  def local(deprecated \\ false)
  def local(false), do: "10"
  def local(true), do: "11"

  def remote(deprecated \\ false)
  def remote(false), do: "20"
  def remote(true), do: "21"

  def global(deprecated \\ false)
  def global(false), do: "30"
  def global(true), do: "31"

  def auto(deprecated \\ false)
  def auto(false), do: "40"
  def auto(true), do: "41"

  def default(deprecated \\ false)
  def default(false), do: "90"
  def default(true), do: "91"
end
