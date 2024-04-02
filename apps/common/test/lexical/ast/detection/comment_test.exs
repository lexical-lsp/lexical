defmodule Lexical.Ast.Detection.CommentTest do
  alias Lexical.Ast.Detection

  use Lexical.Test.DetectionCase,
    for: Detection.Comment,
    assertions: [[:comment, :*]]
end
