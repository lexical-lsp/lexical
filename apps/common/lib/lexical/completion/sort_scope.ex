defmodule Lexical.Completion.SortScope do
  @moduledoc """
  Enumerated categories for sorting completion items.

  The following options are available for all categories, spare variables
  which cannot be deprecated.
  
    * `deprecated?` - Indicates the completion is for a deprecated declaration.
      Defaults to `false`.

    * `low_priority?` - Indicates a completion should be sorted at the bottom of
      its respective scope. Defaults to `false`.
  """

  @doc """
  Intended for variables, which are always local in scope.
  """
  def variable(low_priority? \\ false) do
    "0" <> "0" <> low_priority(low_priority?)
  end

  @doc """
  Intended for declarations (functions and macros) defined in the immediate
  module, or inherited from invoking `use`.
  """
  def local(deprecated? \\ false, low_priority? \\ false) do
    "1" <> extra_order_fields(deprecated?, low_priority?)
  end

  @doc """
  Intended for delcarations defined in other modules than the immediate scope,
  either from one's project, dependencies, or the standard library.
  """
  def remote(deprecated? \\ false, low_priority? \\ false) do
    "2" <> extra_order_fields(deprecated?, low_priority?)
  end

  @doc """
  Intended for declarations available without aliasing, namely those in
  `Kernel` and `Kernel.SpecialForms`.
  """
  def global(deprecated? \\ false, low_priority? \\ false) do
    "3" <> extra_order_fields(deprecated?, low_priority?)
  end

  @doc """
  Aspirationally for declarations that could be auto-aliased into the user's
  immediate module (not yet a feature of Lexical).
  """
  def auto(deprecated? \\ false, low_priority? \\ false) do
    "4" <> extra_order_fields(deprecated?, low_priority?)
  end

  @doc """
  Sorting scope applied to completions that without any sorting scope applied.
  """
  def default(deprecated? \\ false, low_priority? \\ false) do
    "9" <> extra_order_fields(deprecated?, low_priority?)
  end

  defp extra_order_fields(deprecated?, low_priority?) do
    deprecated(deprecated?) <> low_priority(low_priority?)
  end

  defp deprecated(false), do: "0"
  defp deprecated(true), do: "1"

  defp low_priority(false), do: "0"
  defp low_priority(true), do: "1"
end
