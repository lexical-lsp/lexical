defmodule Lexical.Completion.SortScope do
  def local_variables(deprecated \\ false)
  def local_variables(false), do: "000"
  def local_variables(true), do: "001"

  def local_declarations(deprecated \\ false)
  def local_declarations(false), do: "010"
  def local_declarations(true), do: "011"

  def remote_declarations(deprecated \\ false)
  def remote_declarations(false), do: "100"
  def remote_declarations(true), do: "101"

  def global_declarations(deprecated \\ false)
  def global_declarations(false), do: "110"
  def global_declarations(true), do: "111"

  def auto_declarations(deprecated \\ false)
  def auto_declarations(false), do: "200"
  def auto_declarations(true), do: "201"

  def default(deprecated \\ false)
  def default(false), do: "990"
  def default(true), do: "991"
end