defmodule Lexical.RemoteControl.Tracer.Definition do
  alias Lexical.Project
  alias Lexical.SourceFile
  alias Lexical.SourceFile.Range
  alias Lexical.SourceFile.Position
  alias Lexical.SourceFile.Path, as: SourceFilePath

  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Tracer.State
  alias Lexical.RemoteControl.Tracer.ModuleParser

  require Logger

  def definition(%Project{} = project, %SourceFile{} = source_file, {line, column}) do
    text = SourceFile.to_string(source_file)
    context = Code.Fragment.surround_context(text, {line, column})

    case call_kind(context) do
      :module -> module_definition(project, context, source_file, {line, column})
      :function -> function_definition(project, context, source_file)
      _ -> nil
    end
  end

  defp call_kind(context) do
    case context do
      %{context: {:local_or_var, '__MODULE__'}} -> :module
      %{context: {:alias, _alias}} -> :module
      %{context: {:struct, _alias}} -> :module
      %{context: {kind, _}} when kind in [:local_call, :local_or_var] -> :function
      %{context: {:dot, {:alias, _alias}, _call}} -> :function
      _ -> :unknown
    end
  end

  defp module_definition(
         project,
         %{context: {:local_or_var, '__MODULE__'}},
         source_file,
         {line, _column}
       ) do
    range = get_module_range_by_file_and_line(project, source_file.path, line)
    range && %{range: to_source_file_range(range), uri: source_file.uri}
  end

  defp module_definition(project, %{context: {kind, _alias}}, source_file, {line, column})
       when kind in [:struct, :alias] do
    {:ok, fetched} = SourceFile.fetch_line_at(source_file, line - 1)
    {:line, line_text, _, _, _} = fetched
    actual_modules = ModuleParser.modules_at_cursor(line_text, column)

    aliases = get_alias_mapping_by_file_and_line(project, source_file.path, line)
    [head | tail] = actual_modules
    maybe_aliased = Map.get(aliases, to_module(head))

    real_modules =
      if maybe_aliased do
        [maybe_aliased | tail]
      else
        actual_modules
      end

    real_module = to_module(real_modules)

    module_info = get_moudle_info_by_name(project, real_module)

    if is_nil(module_info) do
      Logger.warn("No module info for #{inspect(real_module)}")
    end

    module_info &&
      %{
        range: to_source_file_range(module_info.range),
        uri: SourceFilePath.ensure_uri(module_info.file)
      }
  end

  defp function_definition(project, context, source_file) do
    # Tracer already has the call info
    # We just need to get the call info from the context position
    position = function_call_position(context)

    call =
      if position do
        get_call_by_file_and_position(project, source_file.path, position)
      end

    def_info =
      if call do
        get_def_info_by_mfa(project, call.callee)
      end

    # NOTE: Logging for debugging
    if is_nil(call) do
      Logger.warn("No call for #{inspect(context)}")
    end

    def_info =
      if not is_nil(call) && is_nil(def_info) do
        {m, f, a} = call.callee
        # for default arity
        get_def_info_by_mfa(project, {m, f, a + 1})
      else
        def_info
      end

    def_info &&
      %{
        range: to_source_file_range(def_info.range),
        uri: SourceFilePath.ensure_uri(def_info.file)
      }
  end

  defp function_call_position(%{context: {call_kind, _call}, begin: begin})
       when call_kind in [:local_call, :local_or_var] do
    begin
  end

  defp function_call_position(%{context: {:dot, {:alias, _alias}, call}, end: end_}) do
    {elem(end_, 0), elem(end_, 1) - length(call)}
  end

  defp to_source_file_range(range) do
    %Range{
      start: %Position{line: range.start.line - 1, character: range.start.column - 1},
      end: %Position{line: range.end.line - 1, character: range.end.column - 1}
    }
  end

  defp to_module(modules) when is_list(modules) do
    Module.concat(Elixir, Enum.join(modules, ""))
  end

  defp to_module(module) when is_binary(module) do
    Module.concat(Elixir, module)
  end

  defp get_module_range_by_file_and_line(project, file, line) do
    RemoteControl.call(project, State, :get_module_range_by_file_and_line, [file, line])
  end

  defp get_alias_mapping_by_file_and_line(project, file, line) do
    RemoteControl.call(project, State, :get_alias_mapping_by_file_and_line, [file, line])
  end

  defp get_moudle_info_by_name(project, name) do
    RemoteControl.call(project, State, :get_moudle_info_by_name, [name])
  end

  defp get_call_by_file_and_position(project, file, position) do
    RemoteControl.call(project, State, :get_call_by_file_and_position, [file, position])
  end

  defp get_def_info_by_mfa(project, mfa) do
    RemoteControl.call(project, State, :get_def_info_by_mfa, [mfa])
  end
end
