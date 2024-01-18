defmodule Lexical.RemoteControl.Search.Subject do
  @moduledoc """
  Functions for converting to a search entry's subject field
  """
  alias Lexical.Formats

  def module(module) do
    module
  end

  def module_attribute(module, attribute_name) do
    "#{module}@#{attribute_name}"
  end

  def mfa(module, function, arity) do
    Formats.mfa(module, function, arity)
  end
end
