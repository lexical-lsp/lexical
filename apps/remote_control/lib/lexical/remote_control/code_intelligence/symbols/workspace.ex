defmodule Lexical.RemoteControl.CodeIntelligence.Symbols.Workspace do
  defmodule Link do
    defstruct [:uri, :range, :detail_range]

    def new(uri, range, detail_range \\ nil) do
      %__MODULE__{uri: uri, range: range, detail_range: detail_range}
    end
  end

  alias Lexical.Document
  alias Lexical.Formats
  alias Lexical.RemoteControl.Search.Indexer.Entry

  defstruct [:name, :type, :link, container_name: nil]

  def from_entry(%Entry{} = entry) do
    link =
      entry.path
      |> Document.Path.to_uri()
      |> Link.new(entry.block_range, entry.range)

    name = symbol_name(entry.type, entry)

    %__MODULE__{
      name: name,
      type: entry.type,
      link: link
    }
  end

  defp symbol_name(fun, entry)
       when fun in [:function, :public_function, :private_function] do
    [name_and_arity, local_module] =
      entry.subject
      |> String.split(".")
      |> Enum.reverse()
      |> Enum.take(2)

    local_module <> "." <> name_and_arity
  end

  @module_types [
    :struct,
    :module,
    :protocol,
    :protocol_implementation
  ]

  defp symbol_name(type, entry) when type in @module_types do
    Formats.module(entry.subject)
  end

  defp symbol_name(_, entry),
    do: entry.subject
end
