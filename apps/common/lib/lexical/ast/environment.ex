defmodule Lexical.Ast.Environment do
  @type t :: any

  @type maybe_binary :: binary | nil
  @type token_value :: String.t() | charlist
  @type lexer_token :: {atom, token_value}
  @type token_count :: pos_integer | :all

  @type context_type :: :pipe | :alias | :struct_reference | :function_capture | :bitstring

  @callback in_context?(t, context_type) :: boolean

  @callback empty?(maybe_binary) :: boolean
  @callback prefix_tokens(t) :: [lexer_token]
  @callback prefix_tokens(t, token_count) :: [lexer_token]
end
