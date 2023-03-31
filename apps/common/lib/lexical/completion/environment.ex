defmodule Lexical.Completion.Environment do
  @type t :: any

  @type maybe_binary :: binary | nil

  @callback function_capture?(t) :: boolean
  @callback struct_reference?(t) :: boolean
  @callback pipe?(t) :: boolean
  @callback empty?(maybe_binary) :: boolean
  @callback last_word(t) :: String.t()
end
