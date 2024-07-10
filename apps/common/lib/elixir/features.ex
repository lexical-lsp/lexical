defmodule Elixir.Features do
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
end
