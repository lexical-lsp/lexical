defmodule Lexical.RemoteControl.Build.Error do
  alias Mix.Task.Compiler.Diagnostic

  require Logger

  # Parse errors happen during Code.string_to_quoted and are raised as SyntaxErrors, and TokenMissingErrors.
  def parse_error_to_diagnostic(context, message_info, token) do
    %Mix.Task.Compiler.Diagnostic{
      file: nil,
      severity: :error,
      position: context_to_position(context),
      compiler_name: "Elixir",
      message: message_info_to_binary(message_info, token)
    }
  end

  def error_to_diagnostic(%CompileError{} = compile_error, _stack, _quoted_ast) do
    %Diagnostic{
      message: compile_error.description,
      position: position(compile_error.line),
      compiler_name: "Elixir",
      file: compile_error.file,
      severity: :error
    }
  end

  def error_to_diagnostic(%FunctionClauseError{} = function_clause, stack, _quoted_ast) do
    %Diagnostic{
      message: Exception.message(function_clause),
      position: stack_to_position(stack),
      file: nil,
      severity: :error,
      compiler_name: "Elixir"
    }
  end

  def error_to_diagnostic(%UndefinedFunctionError{} = undefined_function, stack, quoted_ast) do
    [{module, function, arguments, _} | _] = stack
    arity = length(arguments)
    mfa = {module, function, arity}

    %Diagnostic{
      message: Exception.message(undefined_function),
      position: mfa_to_position(mfa, quoted_ast),
      file: stack_to_file(stack),
      severity: :error,
      compiler_name: "Elixir"
    }
  end

  def message_to_diagnostic(message_string) do
    message_string
    |> extract_individual_messages()
    |> Enum.map(&do_message_to_diagnostic/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_individual_messages(messages) do
    messages
    |> extract_individual_messages([], [])
  end

  defp extract_individual_messages(<<>>, current_message, messages) do
    [current_message | messages]
    |> Enum.map(&to_message/1)
    |> Enum.reverse()
  end

  defp extract_individual_messages(<<"error:", rest::binary>>, current_message, messages) do
    extract_individual_messages(rest, ["error:"], [current_message | messages])
  end

  defp extract_individual_messages(<<"warning:", rest::binary>>, current_message, messages) do
    extract_individual_messages(rest, ["warning:"], [current_message | messages])
  end

  defp extract_individual_messages(<<c::utf8, rest::binary>>, current_message, messages) do
    extract_individual_messages(rest, [current_message, c], messages)
  end

  defp to_message(iodata) do
    iodata
    |> IO.iodata_to_binary()
    |> String.trim()
  end

  defp mfa_to_position({module, function, arity}, quoted_ast) do
    # Because elixir's Code module has less than stellr line reporting, I think the best we can
    # do here is to get the error from the stack trace

    module_path =
      module
      |> Module.split()
      |> Enum.map(&String.to_atom/1)

    traverser = fn
      {{:., _, [{:__aliases__, _, ^module_path}, ^function]}, context, arguments} = ast, _
      when length(arguments) == arity ->
        {ast, context}

      ast, nil ->
        {ast, nil}

      ast, found ->
        {ast, found}
    end

    {_, context} = Macro.traverse(quoted_ast, nil, traverser, fn ast, acc -> {ast, acc} end)

    cond do
      Keyword.has_key?(context, :line) and Keyword.has_key?(context, :column) ->
        position(context[:line], context[:column])

      Keyword.has_key?(context, :line) ->
        position(context[:line])

      true ->
        nil
    end
  end

  defp stack_to_position([{_module, _function, _arity, context} | _] = _stack) do
    context_to_position(context)
  end

  defp stack_to_file(stacktrace) do
    case Enum.find(stacktrace, fn trace_element -> elem(trace_element, 0) == :elixir_eval end) do
      {:elixir_eval, _, _, position_kw} ->
        Keyword.get(position_kw, :file)

      _ ->
        nil
    end
  end

  defp context_to_position(context) do
    cond do
      Keyword.has_key?(context, :line) and Keyword.has_key?(context, :column) ->
        position(context[:line], context[:column])

      Keyword.has_key?(context, :line) ->
        position(context[:line])

      true ->
        nil
    end
  end

  defp do_message_to_diagnostic("") do
    nil
  end

  defp do_message_to_diagnostic("warning: redefining module" <> _) do
    nil
  end

  defp do_message_to_diagnostic(message) do
    message_lines = String.split(message, "\n")

    with {:ok, location_line} <- find_location(message_lines),
         {:ok, {file, line, column, mfa}} <- parse_location(location_line) do
      %Diagnostic{
        compiler_name: "Elixir",
        details: mfa,
        message: message,
        file: file,
        position: position(line, column),
        severity: :warning
      }
    else
      _ ->
        nil
    end
  end

  # This regex captures file / line based locations (file.ex:3)
  @file_and_line_re ~r/\s+([^:]+):(\d+)/
  # This regex matches the  more detailed locations that contain the
  # file, line, and the mfa of the error
  @location_re ~r/\s+([^:]+):(\d+):\s+([^\.]+)\.(\w+)\/(\d+)?/
  def parse_location(location_string) do
    with [] <- Regex.scan(@location_re, location_string),
         [[_, file, line]] <- Regex.scan(@file_and_line_re, location_string) do
      line = String.to_integer(line)
      column = 0
      location = {file, line, column, nil}
      {:ok, location}
    else
      [[_, file, line, module, function, arity]] ->
        line = String.to_integer(line)
        column = 0
        module = Module.concat([module])
        function = String.to_atom(function)
        arity = String.to_integer(arity)
        location = {file, line, column, {module, function, arity}}
        {:ok, location}

      _ ->
        :error
    end
  end

  defp find_location(lines) do
    Enum.find(lines, fn
      line when is_binary(line) ->
        Regex.scan(@location_re, line) != [] or Regex.scan(@file_and_line_re, line) != []

      _ ->
        false
    end)
    |> case do
      line when is_binary(line) -> {:ok, line}
      nil -> :error
    end
  end

  defp position(line) do
    line
  end

  defp position(line, column) do
    {line, column}
  end

  defp message_info_to_binary(message_info, token) when is_binary(message_info) do
    message_info <> token
  end

  defp message_info_to_binary({header, footer}, token) do
    header <> token <> footer
  end
end
