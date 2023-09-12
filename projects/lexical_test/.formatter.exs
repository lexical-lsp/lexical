# Used by "mix format"
test_asserts = [
  assert_normalized: 1
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: test_asserts,
  export: [
    locals_without_parens: test_asserts
  ]
]
