defmodule Lexical.RemoteControl.Search.Indexer.Source.Block do
  @moduledoc """
  A struct that represents a block of source code
  """
  defstruct [:starts_at, :ends_at, :ref, :parent_ref]

  def root do
    %__MODULE__{ref: :root}
  end

  def new(starts_at, ends_at) do
    %__MODULE__{starts_at: starts_at, ends_at: ends_at, ref: make_ref()}
  end
end
