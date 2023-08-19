defmodule Lexical.Server.Provider.Handlers.Hover do
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Responses
  alias Lexical.Protocol.Types.Hover
  alias Lexical.Protocol.Types.Markup
  alias Lexical.RemoteControl
  alias Lexical.Server.CodeIntelligence.Entity
  alias Lexical.Server.Provider.Env

  require Logger

  def handle(%Requests.Hover{} = request, %Env{} = env) do
    maybe_hover =
      with {:ok, {:module, module}} <- Entity.resolve(request.document, request.position),
           {:ok, doc_content} <- module_doc_content(env.project, module) do
        module_name = module |> to_string() |> String.replace_prefix("Elixir.", "")

        content = """
        ### #{module_name}

        #{doc_content}\
        """

        %Hover{contents: %Markup.Content{kind: :markdown, value: content}}
      else
        error ->
          Logger.warning("Could not resolve hover request, got: #{inspect(error)}")
          nil
      end

    {:reply, Responses.Hover.new(request.id, maybe_hover)}
  end

  defp module_doc_content(project, module) do
    case fetch_docs(project, module) do
      {:ok, %{module_doc: doc}} when is_binary(doc) ->
        {:ok, doc}

      {:ok, %{module_doc: :none}} ->
        {:ok, "*This module is undocumented.*\n"}

      {:ok, %{module_doc: :hidden}} ->
        {:ok, "*This module is private.*\n"}

      {:ok, other} ->
        {:error, {:unexpected, other}}

      error ->
        error
    end
  end

  defp fetch_docs(project, module) do
    with {:docs_v1, _annotation, _lang, _format, module_doc, _meta, docs} <-
           RemoteControl.Api.docs(project, module) do
      {:ok, %{module_doc: parse_module_doc(module_doc), docs: docs}}
    end
  end

  defp parse_module_doc(%{"en" => module_doc}), do: module_doc
  defp parse_module_doc(other) when is_atom(other), do: other
end
