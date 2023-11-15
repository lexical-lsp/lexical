defmodule Lexical.Ast.Detection.AliasTest do
  alias Lexical.Ast.Detection

  use Lexical.Test.DetectionCase,
    for: Detection.Alias,
    assertions: [[:alias, :*]]
end
