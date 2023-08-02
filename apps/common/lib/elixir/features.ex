defmodule Elixir.Features do
  def with_diagnostics? do
    function_exported?(Code, :with_diagnostics, 1)
  end

  def compile_wont_change_directory? do
    Version.match?(System.version(), ">= 1.15.0")
  end

  def config_reader? do
    Version.match?(System.version(), ">= 1.11.0")
  end
end
