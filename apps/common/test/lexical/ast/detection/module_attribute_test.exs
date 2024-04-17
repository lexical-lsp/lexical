defmodule Lexical.Ast.Detection.ModuleAttributeTest do
  alias Lexical.Ast.Detection

  use Lexical.Test.DetectionCase,
    for: Detection.ModuleAttribute,
    assertions: [
      [:module_attribute, :*],
      [:callbacks, :*]
    ],
    skip: [
      [:doc, :*],
      [:module_doc, :*],
      [:spec, :*],
      [:type, :*]
    ],
    variations: [:module]
end
