defmodule Lexical.Server.Provider.Handlers.Hover do
  alias Lexical.Ast
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Responses
  alias Lexical.Protocol.Types.Hover
  alias Lexical.Protocol.Types.Markup
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.CodeIntelligence.Docs
  alias Lexical.Server.CodeIntelligence.Entity
  alias Lexical.Server.Provider.Env

  require Logger

  def handle(%Requests.Hover{} = request, %Env{} = env) do
    maybe_hover =
      with {:ok, entity, _elixir_range} <- Entity.resolve(request.document, request.position),
           {:ok, sections} <- hover_content(entity, env) do
        content = Enum.join(sections, "\n---\n\n")
        %Hover{contents: %Markup.Content{kind: :markdown, value: content}}
      else
        error ->
          Logger.warning("Could not resolve hover request, got: #{inspect(error)}")
          nil
      end

    {:reply, Responses.Hover.new(request.id, maybe_hover)}
  end

  defp hover_content({kind, module}, env) when kind in [:module, :struct] do
    with {:ok, module_docs} <- RemoteControl.Api.docs(env.project, module) do
      doc_content = module_doc_content(module_docs.doc)
      defs_content = module_defs_content(kind, module_docs)
      header_content = format_header(kind, module_docs)

      sections =
        [
          """
          ```elixir
          #{header_content}
          ```
          """,
          defs_content,
          doc_content
        ]
        |> Enum.filter(&Function.identity/1)

      {:ok, sections}
    end
  end

  defp format_header(:module, %Docs{module: module}) do
    Ast.Module.name(module)
  end

  defp format_header(:struct, %Docs{module: module}) do
    "%#{Ast.Module.name(module)}{}"
  end

  defp module_doc_content(s) when is_binary(s), do: s
  defp module_doc_content(:none), do: "*This module is undocumented.*\n"
  defp module_doc_content(:hidden), do: "*This module is private.*\n"

  defp module_defs_content(:module, _), do: nil

  defp module_defs_content(:struct, docs) do
    defs =
      for entry <- Map.get(docs.types, :t, []),
          def <- entry.defs do
        {entry.arity, def}
      end
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    if defs != [] do
      """
      #### Struct

      ```elixir
      #{Enum.join(defs, "\n")}
      ```
      """
    end
  end
end
