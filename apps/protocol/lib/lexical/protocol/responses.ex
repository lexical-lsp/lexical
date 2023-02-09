defmodule Lexical.Protocol.Responses do
  alias Lexical.Protocol.Proto
  alias Lexical.Protocol.Types

  defmodule InitializeResult do
    use Proto

    defresponse Types.Initizlize.Result
  end

  defmodule FindReferences do
    use Proto

    defresponse optional(list_of(Types.Location))
  end

  defmodule Formatting do
    use Proto

    defresponse optional(list_of(Types.TextEdit))
  end

  defmodule CodeAction do
    use Proto

    defresponse optional(list_of(Types.CodeAction))
  end

  defmodule Completion do
    use Proto

    defresponse optional(list_of(one_of([list_of(Types.Completion.Item), Types.Completion.List])))
  end
end
