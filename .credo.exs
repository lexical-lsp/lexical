%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "src/", "web/", "apps/"],
        excluded: ["apps/remote_control/test/fixtures/**/*.ex"]
      },
      plugins: [],
      requires: [],
      strict: true,
      parse_timeout: 5000,
      color: true,
      checks: [
        {Credo.Check.Design.AliasUsage, if_nested_deeper_than: 3, if_called_more_often_than: 1},
        {Credo.Check.Readability.AliasOrder, []},
        {Credo.Check.Readability.ModuleDoc, false},
        {Credo.Check.Readability.PreferImplicitTry, false},
        {Credo.Check.Refactor.CyclomaticComplexity, max_complexity: 10},
        {Credo.Check.Refactor.Nesting, max_nesting: 3},
        {Credo.Check.Refactor.PipeChainStart, []}
      ]
    }
  ]
}
