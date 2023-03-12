# Used by "mix format"
[
  inputs:
    Enum.flat_map(
      ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
      &Path.wildcard(&1, match_dot: true)
    ) --
      [
        "test/fixtures/compilation_errors/lib/compilation_errors.ex",
        "test/fixtures/parse_errors/lib/parse_errors.ex"
      ]
]
