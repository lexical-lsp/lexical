defmodule Lexical.SourceFile.Line do
  import Record

  defrecord :line, text: nil, ending: nil, line_number: 0, ascii?: true

  @type t ::
          record(:line,
            text: String.t(),
            ending: String.t(),
            line_number: non_neg_integer,
            ascii?: boolean
          )
end
