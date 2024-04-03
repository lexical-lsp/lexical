defmodule Lexical.Ast.Detection.ModuleAttributeTest do
  alias Lexical.Ast.Detection

  use Lexical.Test.DetectionCase,
    for: Detection.ModuleAttribute,
    assertions: [
      [:module_attribute, :*],
      [:callbacks, :*],
      [:doc, :*],
      [:module_doc, :*]
    ],
    skip: [[:type, :*], [:spec, :*]],
    variations: [:module]
end
