# defmodule Lexical.Server.Provider.Handlers.FindReferences do
#   alias Lexical.Build
#   alias Lexical.Document
#   alias Lexical.Protocol.Requests.FindReferences
#   alias Lexical.Protocol.Responses
#   alias Lexical.Protocol.Types.Location
#   alias Lexical.Ranged
#   alias Lexical.Tracer

#   require Logger

#   def handle(%FindReferences{} = request, _) do
#     source_file = request.source_file
#     pos = request.position
#     trace = Tracer.get_trace()
#     # elixir_ls uses 1 based columns, so add 1 here.
#     character = pos.character + 1

#     Build.with_lock(fn ->
#       references =
#         source_file
#         |> Document.to_string()
#         |> ElixirSense.references(pos.line, character, trace)
#         |> Enum.reduce([], fn reference, acc ->
#           case build_reference(reference, source_file) do
#             {:ok, location} ->
#               [location | acc]

#             _ ->
#               acc
#           end
#         end)
#         |> Enum.reverse()

#       response = Responses.FindReferences.new(request.id, references)
#       Logger.info("found #{length(references)} refs")
#       {:reply, response}
#     end)
#   end

#   defp build_reference(%{range: _, uri: _} = elixir_sense_reference, current_source_file) do
#     with {:ok, source_file} <- get_source_file(elixir_sense_reference, current_source_file),
#          {:ok, elixir_range} <- Ranged.Native.from_lsp(elixir_sense_reference, source_file),
#          {:ok, ls_range} <- Ranged.Lsp.from_native(elixir_range, source_file) do
#       uri = Document.Path.ensure_uri(source_file.uri)
#       {:ok, Location.new(uri: uri, range: ls_range)}
#     end
#   end

#   defp get_source_file(%{uri: nil}, current_source_file) do
#     {:ok, current_source_file}
#   end

#   defp get_source_file(%{uri: uri}, _) do
#     Document.Store.open_temporary(uri)
#   end
# end
