defmodule Elixir.Features do
  alias Lexical.VM.Versions

  def with_diagnostics? do
    function_exported?(Code, :with_diagnostics, 1)
  end

  def compile_keeps_current_directory? do
    Version.match?(System.version(), ">= 1.15.0")
  end

  def after_verify? do
    Version.match?(System.version(), ">= 1.14.0")
  end

  def details_in_context? do
    Version.match?(System.version(), ">= 1.16.0")
  end

  def span_in_diagnostic? do
    Version.match?(System.version(), ">= 1.16.0")
  end

  def contains_set_theoretic_types? do
    Version.match?(System.version(), ">= 1.17.0")
  end

  @doc """
  Whether the `:compressed` ETS table option can be safely used.

  A bug in at least Erlang/OTP 27.0.0 and 27.0.1 can cause a segfault
  when traversing the entire table with something like `:ets.foldl/3`
  if the `:compressed` table option is used. When this is fixed, we can
  change the version check to `"< 27.0.0 or >= 27.X"`.
  """
  def can_use_compressed_ets_table? do
    Version.match?(Versions.current().erlang, "< 27.0.0")
  end
end
