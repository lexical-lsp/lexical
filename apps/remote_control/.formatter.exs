# Used by "mix format"
current_directory = Path.dirname(__ENV__.file)

impossible_to_format = [
  Path.join(["test", "fixtures", "compilation_errors", "lib", "compilation_errors.ex"]),
  Path.join(["test", "fixtures", "parse_errors", "lib", "parse_errors.ex"])
]

locals_without_parens = [report_progress: 2]

[
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens],
  import_deps: [:common],
  inputs:
    Enum.flat_map(
      [
        Path.join(current_directory, "*.exs"),
        Path.join(current_directory, "{lib,test}/**/*.{ex,exs}")
      ],
      &Path.wildcard(&1, match_dot: true)
    ) -- impossible_to_format
]
