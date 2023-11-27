defmodule Lexical.Ast.Detection.SpecTest do
  alias Lexical.Ast.Detection

  use Lexical.Test.DetectionCase,
    for: Detection.Spec,
    assertions: [[:spec, :*]]
end
