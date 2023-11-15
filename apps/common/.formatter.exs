# Used by "mix format"
eventual_assertions = [
  assert_eventually: 1,
  assert_eventually: 2,
  refute_eventually: 1,
  refute_eventually: 2
]

detected_assertions = [
  assert_detected: 1,
  assert_detected: 2,
  refute_detected: 1,
  refute_detected: 2
]

assertions = eventual_assertions ++ detected_assertions

[
  inputs: [
    "{mix,.formatter}.exs",
    "{config,test}/**/*.{ex,exs}",
    "lib/lexical/**/*.{ex,ex}",
    "lib/mix/**/*.{ex,exs}"
  ],
  locals_without_parens: assertions,
  export: [locals_without_parens: assertions]
]
