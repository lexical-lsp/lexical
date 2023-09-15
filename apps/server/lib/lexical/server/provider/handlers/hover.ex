defmodule Lexical.Server.Provider.Handlers.Hover do
  alias Lexical.Ast
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Responses
  alias Lexical.Protocol.Types.Hover
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.CodeIntelligence.Docs
  alias Lexical.Server.CodeIntelligence.Entity
  alias Lexical.Server.Provider.Env
  alias Lexical.Server.Provider.Markdown

  require Logger

  def handle(%Requests.Hover{} = request, %Env{} = env) do
    maybe_hover =
      with {:ok, entity, range} <- Entity.resolve(request.document, request.position),
           {:ok, sections} <- hover_content(entity, env) do
        content =
          sections
          |> Markdown.join_sections()
          |> Markdown.to_content()

        %Hover{contents: content, range: range}
      else
        error ->
          Logger.warning("Could not resolve hover request, got: #{inspect(error)}")
          nil
      end

    {:reply, Responses.Hover.new(request.id, maybe_hover)}
  end

  defp hover_content({kind, module}, env) when kind in [:module, :struct] do
    case RemoteControl.Api.docs(env.project, module) do
      {:ok, %Docs{doc: doc} = module_docs} when is_binary(doc) ->
        header_content = module_header(kind, module_docs)
        defs_content = module_defs_content(kind, module_docs)
        footer_content = module_footer_content(kind, module_docs)

        sections = [
          header_content,
          defs_content,
          doc,
          footer_content
        ]

        {:ok, sections}

      _ ->
        {:error, :no_doc}
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
    |> Markdown.code_block()
  end

  defp module_header(:struct, %Docs{module: module}) do
    "%#{Ast.Module.name(module)}{}"
    |> Markdown.code_block()
  end

  defp module_defs_content(:module, _), do: nil

  defp module_defs_content(:struct, docs) do
    struct_type_defs =
      docs.types
      |> Map.get(:t, [])
      |> sort_entries()
      |> Enum.flat_map(& &1.defs)

    if struct_type_defs != [] do
      struct_type_defs
      |> Enum.join("\n")
      |> Markdown.code_block()
      |> Markdown.section(header: "Struct")
    end
  end

  defp module_footer_content(:module, docs) do
    callback_defs =
      docs.callbacks
      |> Map.values()
      |> List.flatten()
      |> sort_entries()
      |> Enum.flat_map(& &1.defs)

    if callback_defs != [] do
      callback_defs
      |> Enum.map_join("\n", &("@callback " <> &1))
      |> Markdown.code_block()
      |> Markdown.section(header: "Callbacks")
    end
  end

  defp module_footer_content(:struct, _docs), do: nil

  defp entry_sections(%Docs.Entry{} = entry) do
    [signature | _] = entry.signature
    module_name = Ast.Module.name(entry.module)
    specs = Enum.map_join(entry.defs, "\n", &("@spec " <> &1))

    [
      Markdown.code_block(module_name <> "." <> signature),
      if specs != "" do
        specs
        |> Markdown.code_block()
        |> Markdown.section(header: "Specs")
      end,
      entry_doc_content(entry.doc)
    ]
  end

  defp entry_doc_content(s) when is_binary(s), do: s
  defp entry_doc_content(_), do: nil

  defp sort_entries(entries) do
    Enum.sort_by(entries, &{&1.name, &1.arity})
  end
end
