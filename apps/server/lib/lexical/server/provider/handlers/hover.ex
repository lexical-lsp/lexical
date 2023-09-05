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
        content =
          sections
          |> Enum.filter(&(is_binary(&1) and &1 != ""))
          |> Enum.join("\n---\n\n")

        %Hover{contents: %Markup.Content{kind: :markdown, value: content}}
      else
        error ->
          Logger.warning("Could not resolve hover request, got: #{inspect(error)}")
          nil
      end

    {:reply, Responses.Hover.new(request.id, maybe_hover)}
  end

  defp hover_content({kind, module}, env) when kind in [:module, :struct] do
    with {:ok, %Docs{} = module_docs} <- RemoteControl.Api.docs(env.project, module) do
      doc_content = module_doc_content(module_docs.doc)
      defs_content = module_defs_content(kind, module_docs)
      header_content = module_header(kind, module_docs)

      sections = [
        header_content,
        defs_content,
        doc_content
      ]

      {:ok, sections}
    end
  end

  defp hover_content({:call, module, fun, arity}, env) do
    with {:ok, %Docs{} = module_docs} <- RemoteControl.Api.docs(env.project, module),
         {:ok, entries} <- Map.fetch(module_docs.functions_and_macros, fun) do
      sections =
        entries
        |> Enum.sort_by(& &1.arity)
        |> Enum.filter(&(&1.arity >= arity))
        |> Enum.flat_map(&entry_sections/1)

      {:ok, sections}
    end
  end

  defp module_header(:module, %Docs{module: module}) do
    module
    |> Ast.Module.name()
    |> md_elixir_block()
  end

  defp module_header(:struct, %Docs{module: module}) do
    "%#{Ast.Module.name(module)}{}"
    |> md_elixir_block()
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
      formatted_defs = defs |> Enum.join("\n") |> md_elixir_block()

      """
      #### Struct

      #{formatted_defs}\
      """
    end
  end

  defp entry_sections(%Docs.Entry{} = entry) do
    [signature | _] = entry.signature
    module_name = Ast.Module.name(entry.module)
    specs = Enum.map_join(entry.defs, "\n", &("@spec " <> &1))

    [
      md_elixir_block(module_name <> "." <> signature),
      if specs != "" do
        """
        #### Specs

        #{md_elixir_block(specs)}\
        """
      end,
      entry_doc_content(entry.doc)
    ]
  end

  defp entry_doc_content(s) when is_binary(s), do: s
  defp entry_doc_content(:none), do: nil
  defp entry_doc_content(:hidden), do: "*This function is private.*\n"

  defp md_elixir_block(inner) do
    """
    ```elixir
    #{inner}
    ```
    """
  end
end
