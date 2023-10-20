defmodule Lexical.Server.Provider.Handlers.Hover do
  alias Lexical.Ast
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Responses
  alias Lexical.Protocol.Types.Hover
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.CodeIntelligence.Docs
  alias Lexical.RemoteControl.CodeIntelligence.Entity
  alias Lexical.Server.Provider.Env
  alias Lexical.Server.Provider.Markdown

  require Logger

  def handle(%Requests.Hover{} = request, %Env{} = env) do
    maybe_hover =
      with {:ok, entity, range} <- Entity.resolve(request.document, request.position),
           {:ok, markdown} <- hover_content(entity, env) do
        content = Markdown.to_content(markdown)
        %Hover{contents: content, range: range}
      else
        error ->
          Logger.warning("Could not resolve hover request, got: #{inspect(error)}")
          nil
      end

    {:reply, Responses.Hover.new(request.id, maybe_hover)}
  end

  defp hover_content({kind, module}, env) when kind in [:module, :struct] do
    case RemoteControl.Api.docs(env.project, module, exclude_hidden: false) do
      {:ok, %Docs{} = module_docs} ->
        header = module_header(kind, module_docs)
        types = module_header_types(kind, module_docs)

        additional_sections = [
          module_doc(module_docs.doc),
          module_footer(kind, module_docs)
        ]

        if Enum.all?([types | additional_sections], &empty?/1) do
          {:error, :no_doc}
        else
          header_block = "#{header}\n\n#{types}" |> String.trim() |> Markdown.code_block()
          {:ok, Markdown.join_sections([header_block | additional_sections])}
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
        |> Enum.map(&entry_content/1)

      {:ok, Markdown.join_sections(sections, Markdown.separator())}
    end
  end

  defp hover_content({:type, module, type, arity}, env) do
    with {:ok, %Docs{} = module_docs} <- RemoteControl.Api.docs(env.project, module),
         {:ok, entries} <- Map.fetch(module_docs.types, type) do
      case Enum.find(entries, &(&1.arity == arity)) do
        %Docs.Entry{} = entry ->
          {:ok, entry_content(entry)}

        _ ->
          {:error, :no_type}
      end
    end
  end

  defp module_header(:module, %Docs{module: module}) do
    Ast.Module.name(module)
  end

  defp module_header(:struct, %Docs{module: module}) do
    "%#{Ast.Module.name(module)}{}"
  end

  defp module_header_types(:module, %Docs{}), do: ""

  defp module_header_types(:struct, %Docs{} = docs) do
    docs.types
    |> Map.get(:t, [])
    |> sort_entries()
    |> Enum.flat_map(& &1.defs)
    |> Enum.join("\n\n")
  end

  defp module_doc(s) when is_binary(s), do: s
  defp module_doc(_), do: nil

  defp module_footer(:module, docs) do
    callbacks = format_callbacks(docs.callbacks)

    unless empty?(callbacks) do
      Markdown.section(callbacks, header: "Callbacks")
    end
  end

  defp module_footer(:struct, _docs), do: nil

  defp entry_content(%Docs.Entry{kind: fn_or_macro} = entry)
       when fn_or_macro in [:function, :macro] do
    call_header = call_header(entry)
    specs = Enum.map_join(entry.defs, "\n", &("@spec " <> &1))

    header =
      [call_header, specs]
      |> Markdown.join_sections()
      |> String.trim()
      |> Markdown.code_block()

    Markdown.join_sections([header, entry_doc_content(entry.doc)])
  end

  defp entry_content(%Docs.Entry{kind: :type} = entry) do
    header =
      Markdown.code_block("""
      #{call_header(entry)}

      #{type_defs(entry)}\
      """)

    Markdown.join_sections([header, entry_doc_content(entry.doc)])
  end

  @one_line_header_cutoff 50

  defp call_header(%Docs.Entry{kind: :type} = entry) do
    module_name = Ast.Module.name(entry.module)

    one_line_header = "#{module_name}.#{entry.name}/#{entry.arity}"

    two_line_header =
      "#{last_module_name(module_name)}.#{entry.name}/#{entry.arity}\n#{module_name}"

    if String.length(one_line_header) >= @one_line_header_cutoff do
      two_line_header
    else
      one_line_header
    end
  end

  defp call_header(%Docs.Entry{kind: maybe_macro} = entry) do
    [signature | _] = entry.signature
    module_name = Ast.Module.name(entry.module)

    macro_prefix =
      if maybe_macro == :macro do
        "(macro) "
      else
        ""
      end

    one_line_header = "#{macro_prefix}#{module_name}.#{signature}"

    two_line_header =
      "#{macro_prefix}#{last_module_name(module_name)}.#{signature}\n#{module_name}"

    if String.length(one_line_header) >= @one_line_header_cutoff do
      two_line_header
    else
      one_line_header
    end
  end

  defp last_module_name(module_name) do
    module_name
    |> String.split(".")
    |> List.last()
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
