defmodule Lexical.Ast.Detection.BitstringTest do
  use Lexical.Test.DetectionCase,
    for: Lexical.Ast.Detection.Bitstring,
    assertions: [[:bitstring, :*]],
    variations: [:match, :function_arguments, :function_body]
end
