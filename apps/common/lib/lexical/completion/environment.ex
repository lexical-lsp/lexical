defmodule Lexical.Completion.Environment do
  @type t :: any

  @type maybe_binary :: binary | nil
  @type token_value :: String.t() | charlist
  @type lexer_token :: {atom, token_value}
  @type token_count :: pos_integer | :all

  @callback function_capture?(t) :: boolean
  @callback struct_reference?(t) :: boolean
  @callback pipe?(t) :: boolean
  @callback in_bitstring?(t) :: boolean
  @callback empty?(maybe_binary) :: boolean
  @callback last_word(t) :: String.t()
  @callback prefix_tokens(t) :: [lexer_token]
  @callback prefix_tokens(t, token_count) :: [lexer_token]
end
