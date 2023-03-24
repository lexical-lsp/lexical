# Used by "mix format"
eventual_assertions = [
  assert_eventually: 1,
  assert_eventually: 2,
  refute_eventually: 1,
  refute_eventually: 2
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: eventual_assertions,
  export: [locals_without_parens: eventual_assertions]
]
