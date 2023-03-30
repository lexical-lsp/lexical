defmodule Lexical.RemoteControl.Tracer.Definition do
  alias Lexical.Project
  alias Lexical.SourceFile
  alias Lexical.SourceFile.Range
  alias Lexical.SourceFile.Position

  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Tracer.State

  def definition(%Project{} = project, %SourceFile{} = source_file, %Position{} = position) do
    text = SourceFile.to_string(source_file)
    context = Code.Fragment.surround_context(text, {position.line + 1, position.character + 1})

    case call_kind(context) do
      # :function -> function_definition(context, source_file)
      :module -> module_definition(project, context, source_file, position)
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
         position
       ) do
    range = get_module_range_by_file_and_line(project, source_file.path, position.line + 1)
    range && %{range: to_source_file_range(range), uri: source_file.uri}
  end

  defp get_module_range_by_file_and_line(project, file, line) do
    RemoteControl.call(project, State, :get_module_range_by_file_and_line, [file, line])
  end

  # defp module_definition(%{context: {kind, _alias}}, file, {line, character})
  #      when kind in [:struct, :alias] do
  #   line_text = File.stream!(file) |> Enum.at(line - 1) |> String.trim_trailing()
  #   actual_modules = ModuleParser.modules_at_cursor(line_text, character)
  #
  #   aliases = State.get_alias_mapping_by_file_and_line(file, line)
  #   [head | tail] = actual_modules
  #   maybe_aliased = Map.get(aliases, to_module(head))
  #
  #   real_modules =
  #     if maybe_aliased do
  #       [maybe_aliased | tail]
  #     else
  #       actual_modules
  #     end
  #
  #   real_module = to_module(real_modules)
  #   real_module
  # end
  #
  # defp to_module(modules) when is_list(modules) do
  #   Module.concat(Elixir, Enum.join(modules, ""))
  # end
  #
  # defp to_module(module) when is_binary(module) do
  #   Module.concat(Elixir, module)
  # end
  #
  # defp function_definition(context, file) do
  #   # Tracer already has the call info
  #   # We just need to get the call info from the context position
  #   position = function_call_position(context)
  #
  #   call =
  #     if position do
  #       State.get_call_by_file_and_position(file, position)
  #     end
  #
  #   if call do
  #     State.get_def_info_by_mfa(call.callee)
  #   end
  # end
  #
  # defp function_call_position(%{context: {call_kind, _call}, begin: begin})
  #      when call_kind in [:local_call, :local_or_var] do
  #   begin
  # end
  #
  # defp function_call_position(%{context: {:dot, {:alias, _alias}, call}, end: end_}) do
  #   {elem(end_, 0), elem(end_, 1) - length(call)}
  # end
  #
  # defp function_call_position(_), do: nil

  defp to_source_file_range(range) do
    %Range{
      start: %Position{line: range.start.line - 1, character: range.start.column - 1},
      end: %Position{line: range.end.line - 1, character: range.end.column - 1}
    }
  end
end
