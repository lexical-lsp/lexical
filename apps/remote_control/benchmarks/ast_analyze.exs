alias Lexical.Document
alias Lexical.Ast

path =
  [__DIR__, "**", "enum.ex"]
  |> Path.join()
  |> Path.wildcard()
  |> List.first()

{:ok, contents} = File.read(path)
doc = Document.new("file://#{path}", contents, 1)

Benchee.run(
  %{
    "Ast.analyze" => fn ->
      Ast.analyze(doc)
    end
  },
  profile_after: true
)
