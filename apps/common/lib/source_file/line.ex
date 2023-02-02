defmodule Lexical.SourceFile.Line do
  import Record

  defrecord :line, text: nil, ending: nil, line_number: 0, ascii?: true
end
