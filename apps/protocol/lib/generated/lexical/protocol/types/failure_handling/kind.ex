# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.FailureHandling.Kind do
  alias Lexical.Protocol.Proto
  use Proto

  defenum abort: "abort",
          transactional: "transactional",
          text_only_transactional: "textOnlyTransactional",
          undo: "undo"
end
