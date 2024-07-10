defmodule Lexical.Server.Provider.Handlers.WorkspaceSymbol do
  alias Lexical.Protocol.Requests.WorkspaceSymbol
  alias Lexical.Protocol.Responses
  alias Lexical.Protocol.Types.Location
  alias Lexical.Protocol.Types.Symbol.Kind, as: SymbolKind
  alias Lexical.Protocol.Types.Workspace.Symbol
  alias Lexical.RemoteControl.Api
  alias Lexical.RemoteControl.CodeIntelligence.Symbols
  alias Lexical.Server.Configuration

  require SymbolKind

  require Logger

  def handle(%WorkspaceSymbol{} = request, %Configuration{} = config) do
    symbols =
      if String.length(request.query) > 1 do
        config.project
        |> Api.workspace_symbols(request.query)
        |> tap(fn symbols -> Logger.info("syms #{inspect(Enum.take(symbols, 5))}") end)
        |> Enum.map(&to_response/1)
      else
        []
      end

    response = Responses.WorkspaceSymbol.new(request.id, symbols)
    {:reply, response}
  end

  def to_response(%Symbols.Workspace{} = root) do
    Symbol.new(
      kind: to_kind(root.type),
      location: to_location(root.link),
      name: root.name,
      container_name: root.container_name
    )
  end

  defp to_location(%Symbols.Workspace.Link{} = link) do
    Location.new(uri: link.uri, range: link.detail_range)
  end

  defp to_kind(:struct), do: :struct
  defp to_kind(:module), do: :module
  defp to_kind({:protocol, _}), do: :module
  defp to_kind({:lx_protocol, _}), do: :module
  defp to_kind(:variable), do: :variable
  defp to_kind({:function, _}), do: :function
  defp to_kind(:module_attribute), do: :constant
  defp to_kind(:ex_unit_test), do: :method
  defp to_kind(:ex_unit_describe), do: :method
  defp to_kind(:ex_unit_setup), do: :method
  defp to_kind(:ex_unit_setup_all), do: :method
  defp to_kind(:type), do: :type_parameter
  defp to_kind(:spec), do: :interface
  defp to_kind(:file), do: :file
end
