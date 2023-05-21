defmodule Lexical.RemoteControl.Build.Error do
  alias Mix.Task.Compiler.Diagnostic

  require Logger

  def normalize_diagnostic(%Diagnostic{message: message} = diagnostic) do
    %{diagnostic | message: IO.iodata_to_binary(message)}
  end

  # Parse errors happen during Code.string_to_quoted and are raised as SyntaxErrors, and TokenMissingErrors.
  def parse_error_to_diagnostics(context, {_error, detail} = message_info, token) do
    detail_diagnostics = detail_diagnostics(detail)
    error = message_info_to_binary(message_info, token)
    error_diagnostics = parse_error_to_diagnostics(context, error, token)
    uniq(error_diagnostics ++ detail_diagnostics)
  end

  def parse_error_to_diagnostics(context, message_info, token) do
    parse_error_diagnostic_functions = [
      &build_end_line_diagnostics/3,
      &build_start_line_diagnostics/3,
      &build_hint_diagnostics/3
    ]

    Enum.flat_map(parse_error_diagnostic_functions, & &1.(context, message_info, token))
  end

  defp uniq(diagnostics) do
    # We need to uniq by position because the same position can be reported
    # and the `end_line_diagnostic` is always the precise one
    extract_line = fn
      %Diagnostic{position: {line, _column}} -> line
      %Diagnostic{position: line} -> line
    end

    Enum.uniq_by(diagnostics, extract_line)
  end

  defp build_end_line_diagnostics(context, message_info, token) do
    [end_line_message | _] = String.split(message_info, "\n")

    [
      %Diagnostic{
        file: nil,
        severity: :error,
        position: context_to_position(context),
        compiler_name: "Elixir",
        message: "#{end_line_message}#{token}"
      }
    ]
  end

  @start_line_regex ~r/(\w+) \(for (.*) starting at line (\d+)\)/
  defp build_start_line_diagnostics(_context, message_info, _token) do
    case Regex.run(@start_line_regex, message_info) do
      [_, missing, token, start_line] ->
        diagnostic = %Diagnostic{
          file: nil,
          severity: :error,
          position: String.to_integer(start_line),
          compiler_name: "Elixir",
          message: "The #{token} here is missing a terminator: #{inspect(missing)}"
        }

        [diagnostic]

      _ ->
        []
    end
  end

  @hint_regex ~r/HINT: .*on line (\d+).*/m
  defp build_hint_diagnostics(_context, message_info, _token) do
    case Regex.run(@hint_regex, message_info) do
      [message, hint_line] ->
        diagnostic = %Diagnostic{
          file: nil,
          severity: :error,
          position: String.to_integer(hint_line),
          compiler_name: "Elixir",
          message: String.replace(message, ~r/on line \d+/, "here")
        }

        [diagnostic]

      _ ->
        []
    end
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
    [{_module, _function, _arity, context} | _] = stack

    %Diagnostic{
      message: Exception.message(function_clause),
      position: context_to_position(context),
      file: nil,
      severity: :error,
      compiler_name: "Elixir"
    }
  end

  def error_to_diagnostic(%Mix.Error{} = error, stack, quoted_ast) do
    [{module, function, arguments, _} | _] = stack

    mfa = {module, function, arguments}

    %Diagnostic{
      message: Exception.message(error),
      position: mfa_to_position(mfa, quoted_ast),
      file: stack_to_file(stack),
      severity: :error,
      compiler_name: "Elixir"
    }
  end

  def error_to_diagnostic(%UndefinedFunctionError{} = undefined_function, stack, quoted_ast) do
    [{module, function, arguments, context} | _] = stack

    if context == [] do
      arity = length(arguments)
      mfa = {module, function, arity}

      %Diagnostic{
        message: Exception.message(undefined_function),
        position: mfa_to_position(mfa, quoted_ast),
        file: stack_to_file(stack),
        severity: :error,
        compiler_name: "Elixir"
      }
    else
      %Diagnostic{
        message: Exception.message(undefined_function),
        position: stack_to_position(stack),
        file: nil,
        severity: :error,
        compiler_name: "Elixir"
      }
    end
  end

  def error_to_diagnostic(%RuntimeError{} = runtime_error, _stack, _quoted_ast) do
    %Diagnostic{
      message: Exception.message(runtime_error),
      position: 1,
      file: nil,
      severity: :error,
      compiler_name: "Elixir"
    }
  end

  def error_to_diagnostic(%ArgumentError{} = argument_error, stack, _quoted_ast) do
    reversed_stack = Enum.reverse(stack)

    [{_, _, _, context}, {_, call, _, second_to_last_context} | _] = reversed_stack

    maybe_pipe_or_struct? = call in [:|>, :__struct__]
    expanding_macro? = second_to_last_context[:file] == 'expanding macro'

    if maybe_pipe_or_struct? or expanding_macro? do
      %Diagnostic{
        message: Exception.message(argument_error),
        position: context_to_position(context),
        file: nil,
        severity: :error,
        compiler_name: "Elixir"
      }
    else
      %Diagnostic{
        message: Exception.message(argument_error),
        position: stack_to_position(stack),
        file: nil,
        severity: :error,
        compiler_name: "Elixir"
      }
    end
  end

  def error_to_diagnostic(%module{} = exception, stack, _quoted_ast)
      when module in [
             Protocol.UndefinedError,
             ExUnit.DuplicateTestError,
             ExUnit.DuplicateDescribeError
           ] do
    %Diagnostic{
      message: Exception.message(exception),
      position: stack_to_position(stack),
      file: nil,
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

    module_path = safe_split(module)

    traverser = fn
      {{:., _, [{:__aliases__, _, ^module_path}, ^function]}, context, arguments} = ast, _
      when length(arguments) == arity ->
        {ast, context}

      {{:., _, [^module_path, ^function]}, context, arguments} = ast, _
      when length(arguments) == arity ->
        {ast, context}

      ast, nil ->
        {ast, nil}

      ast, found ->
        {ast, found}
    end

    {_, context} = Macro.traverse(quoted_ast, nil, traverser, fn ast, acc -> {ast, acc} end)

    cond do
      is_nil(context) ->
        position(0)

      Keyword.has_key?(context, :line) and Keyword.has_key?(context, :column) ->
        position(context[:line], context[:column])

      Keyword.has_key?(context, :line) ->
        position(context[:line])

      true ->
        nil
    end
  end

  defp safe_split(module) do
    module
    |> Atom.to_string()
    |> String.split(".")
    |> case do
      [erlang_module] -> String.to_atom(erlang_module)
      ["Elixir" | elixir_module_path] -> Enum.map(elixir_module_path, &String.to_atom/1)
    end
  end

  defp stack_to_position([{_, target, _, _} | rest])
       when target not in [:__FILE__, :__MODULE__] do
    stack_to_position(rest)
  end

  defp stack_to_position([{_, target, _, context} | _rest])
       when target in [:__FILE__, :__MODULE__] do
    context_to_position(context)
  end

  defp stack_to_position([]) do
    nil
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
         {:ok, {file, line, mfa}} <- parse_location(location_line) do
      %Diagnostic{
        compiler_name: "Elixir",
        details: mfa,
        message: message,
        file: file,
        position: line,
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
      location = {file, line, nil}
      {:ok, location}
    else
      [[_, file, line, module, function, arity]] ->
        line = String.to_integer(line)
        module = Module.concat([module])
        function = String.to_atom(function)
        arity = String.to_integer(arity)
        location = {file, line, {module, function, arity}}
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

  defp message_info_to_binary({header, footer}, token) do
    header <> token <> footer
  end

  @detail_location_re ~r/at line (\d+)/
  defp detail_diagnostics(detail) do
    case Regex.scan(@detail_location_re, detail) do
      [[matched, line_number]] ->
        line_number = String.to_integer(line_number)
        message = String.replace(detail, matched, "here")

        [
          %Diagnostic{
            file: nil,
            severity: :error,
            position: line_number,
            compiler_name: "Elixir",
            message: message
          }
        ]

      _ ->
        []
    end
  end
end
