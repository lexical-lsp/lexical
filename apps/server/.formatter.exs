# Used by "mix format"
imported_deps =
  if Mix.env() == :test do
    [:patch, :common]
  else
    [:common]
  end

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  import_deps: imported_deps
]
