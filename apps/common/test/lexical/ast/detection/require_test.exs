defmodule Lexical.Ast.Detection.RequireTest do
  alias Lexical.Ast.Detection

  use Lexical.Test.DetectionCase,
    for: Detection.Require,
    assertions: [[:require, :*]]
end
