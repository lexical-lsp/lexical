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
      {:ok, %Docs{doc: doc} = module_docs} when doc != :hidden ->
        header_content = module_header(kind, module_docs)
        types_content = module_types(kind, module_docs)
        doc_content = module_doc(doc)
        footer_content = module_footer(kind, module_docs)

        sections = [
          types_content,
          doc_content,
          footer_content
        ]

        if Enum.any?(sections, &(not empty?(&1))) do
          {:ok, [header_content | sections]}
        else
          {:error, :no_doc}
        end

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

  defp hover_content({:type, module, type, arity}, env) do
    with {:ok, %Docs{} = module_docs} <- RemoteControl.Api.docs(env.project, module),
         {:ok, entries} <- Map.fetch(module_docs.types, type) do
      case Enum.find(entries, &(&1.arity == arity)) do
        %Docs.Entry{} = entry ->
          {:ok, entry_sections(entry)}

        _ ->
          {:error, :no_type}
      end
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

  defp module_doc(s) when is_binary(s), do: s
  defp module_doc(_), do: nil

  defp module_types(:module, _), do: nil

  defp module_types(:struct, docs) do
    struct_type_defs =
      docs.types
      |> Map.get(:t, [])
      |> sort_entries()
      |> Enum.flat_map(& &1.defs)

    if struct_type_defs != [] do
      struct_type_defs
      |> Enum.join("\n\n")
      |> Markdown.code_block()
      |> Markdown.section(header: "Struct")
    end
  end

  defp module_footer(:module, docs) do
    callbacks = format_callbacks(docs.callbacks)

    unless empty?(callbacks) do
      Markdown.section(callbacks, header: "Callbacks")
    end
  end

  defp module_footer(:struct, _docs), do: nil

  defp entry_sections(%Docs.Entry{kind: :function} = entry) do
    with [signature | _] <- entry.signature do
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
  end

  defp entry_sections(%Docs.Entry{kind: :type} = entry) do
    module_name = Ast.Module.name(entry.module)

    header = """
    #{module_name}.#{entry.name}/#{entry.arity}

    #{type_defs(entry)}\
    """

    [
      Markdown.code_block(header),
      entry_doc_content(entry.doc)
    ]
  end

  defp type_defs(%Docs.Entry{metadata: %{opaque: true}} = entry) do
    Enum.map_join(entry.defs, "\n", fn def ->
      def
      |> String.split("::", parts: 2)
      |> List.first()
      |> String.trim()
    end)
  end

  defp type_defs(%Docs.Entry{} = entry) do
    Enum.join(entry.defs, "\n")
  end

  defp format_callbacks(callbacks) do
    callbacks
    |> Map.values()
    |> List.flatten()
    |> sort_entries()
    |> Enum.map_join("\n", fn %Docs.Entry{} = entry ->
      header =
        entry.defs
        |> Enum.map_join("\n", &("@callback " <> &1))
        |> Markdown.code_block()

      if is_binary(entry.doc) do
        """
        #{header}
        #{entry_doc_content(entry.doc)}
        """
      else
        header
      end
    end)
  end

  defp entry_doc_content(s) when is_binary(s), do: String.trim(s)
  defp entry_doc_content(_), do: nil

  defp sort_entries(entries) do
    Enum.sort_by(entries, &{&1.name, &1.arity})
  end

  defp empty?(empty) when empty in [nil, "", []], do: true
  defp empty?(_), do: false
end
