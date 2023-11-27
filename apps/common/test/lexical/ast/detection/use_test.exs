defmodule Lexical.Ast.Detection.UseTest do
  alias Lexical.Ast.Detection

  use Lexical.Test.DetectionCase,
    for: Detection.Use,
    assertions: [[:use, :*]]
end
