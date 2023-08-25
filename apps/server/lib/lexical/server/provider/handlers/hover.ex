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
           {:ok, module_docs} <- RemoteControl.Api.docs(env.project, module) do
        module_name = module |> to_string() |> String.replace_prefix("Elixir.", "")
        doc_content = module_doc_content(module_docs.doc)

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

  defp module_doc_content(s) when is_binary(s), do: s
  defp module_doc_content(:none), do: "*This module is undocumented.*\n"
  defp module_doc_content(:hidden), do: "*This module is private.*\n"
end
