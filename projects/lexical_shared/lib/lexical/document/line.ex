defmodule Lexical.Document.Line do
  @moduledoc ~S"""
  A record representing a line of text in a document

  A line contains the following keys:

  `text`: The actual text of the line, without the line ending

  `ending`: The end of line character(s) can be `"\n"`, `"\r"` or `"\r\n"`. The original
  line ending is preserved

  `line_number`: A zero-based line number

  `ascii?`: A boolean representing if this line consists of only ascii text.
  """
  import Record

  @doc """
  Creates or matches a line of text
  """
  defrecord :line, text: nil, ending: nil, line_number: 0, ascii?: true

  @type t ::
          record(:line,
            text: String.t(),
            ending: String.t(),
            line_number: non_neg_integer,
            ascii?: boolean
          )
end
