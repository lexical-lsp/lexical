# Used by "mix format"
proto_dsl = [
  defalias: 1,
  defenum: 1,
  defnotification: 2,
  defnotification: 3,
  defrequest: 3,
  defresponse: 1,
  deftype: 1
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: proto_dsl,
  export: [
    locals_without_parens: proto_dsl
  ]
]
