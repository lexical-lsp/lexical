defmodule Lexical.Protocol.Responses do
  alias Lexical.Proto
  alias Lexical.Proto.Typespecs
  alias Lexical.Protocol.Types

  defmodule InitializeResult do
    use Proto

    defresponse Types.Initialize.Result
  end

  defmodule FindReferences do
    use Proto

    defresponse optional(list_of(Types.Location))
  end

  defmodule GoToDefinition do
    use Proto

    defresponse optional(Types.Location)
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

  defmodule Shutdown do
    use Proto
    # yeah, this is odd... it has no params
    defresponse []
  end

  defmodule Hover do
    use Proto

    defresponse optional(Types.Hover)
  end

  use Typespecs, for: :responses
end
