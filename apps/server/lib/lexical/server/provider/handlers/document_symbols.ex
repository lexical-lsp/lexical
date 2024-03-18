defmodule Lexical.Server.Provider.Handlers.DocumentSymbols do
  alias Lexical.Document
  alias Lexical.Protocol.Requests.DocumentSymbols
  alias Lexical.Protocol.Responses
  alias Lexical.Protocol.Types.Document.Symbol
  alias Lexical.Protocol.Types.Symbol.Kind, as: SymbolKind
  alias Lexical.RemoteControl.Api
  alias Lexical.RemoteControl.CodeIntelligence.Symbols
  alias Lexical.Server.Provider.Env

  require SymbolKind

  def handle(%DocumentSymbols{} = request, %Env{} = env) do
    symbols = Api.document_symbols(env.project, request.document)
    symbols = Enum.map(symbols, &to_response(&1, request.document))
    response = Responses.DocumentSymbols.new(request.id, symbols)

    {:reply, response}
  end

  def to_response(%Symbols.Document{} = root, %Document{} = document) do
    children =
      case root.children do
        list when is_list(list) ->
          Enum.map(list, &to_response(&1, document))

        _ ->
          nil
      end

    Symbol.new(
      name: root.name,
      kind: to_kind(root.type),
      range: root.range,
      selection_range: root.range,
      children: children,
      detail: root.detail
    )
  end

  defp to_kind(:struct), do: :struct
  defp to_kind(:module), do: :module
  defp to_kind(:variable), do: :variable
  defp to_kind(:public_function), do: :function
  defp to_kind(:private_function), do: :function
  defp to_kind(:module_attribute), do: :constant
  defp to_kind(:ex_unit_test), do: :method
  defp to_kind(:ex_unit_describe), do: :method
  defp to_kind(:ex_unit_setup), do: :method
  defp to_kind(:ex_unit_setup_all), do: :method
  defp to_kind(:type), do: :type_parameter
  defp to_kind(:spec), do: :interface
  defp to_kind(_), do: :string
end
