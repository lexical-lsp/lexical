defmodule Lexical.Ast.Detection.StringTest do
  alias Lexical.Ast.Detection

  use Lexical.Test.DetectionCase,
    for: Detection.String,
    assertions: [[:strings, :*]],
    # we skip other tests that have strings in them
    skip: [
      [:doc, :*],
      [:keyword, :multi_line],
      [:module_doc, :*]
    ],
    variations: [
      :function_arguments,
      :function_body,
      :function_call,
      :match,
      :module
    ]
end
