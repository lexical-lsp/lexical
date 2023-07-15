defmodule Lexical.RemoteControl.Build.Error do
  alias Lexical.Document
  alias Lexical.Plugin.V1.Diagnostic.Result
  alias Mix.Task.Compiler

  require Logger

  @elixir_source "Elixir"

  @doc """
  Diagnostics can come from compiling the whole project,
  from compiling individual files, or from erlang's diagnostics (Code.with_diagnostics since elixir1.15),
  so we need to do some post-processing.

  Includes:
    1. Normalize each one to the standard result
    2. Format the message to make it readable in the editor
    3. Remove duplicate messages on the same line
  """
  def refine_diagnostics(diagnostics) do
    diagnostics
    |> Enum.map(fn diagnostic ->
      diagnostic
      |> normalize()
      |> format()
    end)
    |> uniq()
  end

  defp normalize(%Compiler.Diagnostic{} = diagnostic) do
    Result.new(
      diagnostic.file,
      diagnostic.position,
      diagnostic.message,
      diagnostic.severity,
      diagnostic.compiler_name
    )
  end

  defp normalize(%Result{} = result) do
    result
  end

  defp format(%Result{} = result) do
    %Result{result | message: format_message(result.message)}
  end

  defp format_message("undefined" <> _ = message) do
    # All undefined messages explain the *same* thing inside the parentheses,
    # like: `undefined function print/1 (expected Foo to define such a function or for it to be imported,
    #        but none are available)`
    # that makes no sense and just creates noise.
    # So we can remove the things in parentheses

    message
    |> String.split(" (")
    |> List.first()
  end

  defp format_message(message) when is_binary(message) do
    maybe_format_unused(message)
  end

  defp maybe_format_unused(message) do
    # Same reason as the `undefined` message above, we can remove the things in parentheses
    case String.split(message, "is unused (", parts: 2) do
      [prefix, _] ->
        prefix <> "is unused"

      _ ->
        message
    end
  end

  defp reject_zero_line(diagnostics) do
    # Since 1.15, Elixir has some nonsensical error on line 0,
    # e.g.: Can't compile this file
    # We can simply ignore it, as there is a more accurate one
    Enum.reject(diagnostics, fn diagnostic ->
      diagnostic.position == 0
    end)
  end

  defp uniq(diagnostics) do
    # We need to uniq by position because the same position can be reported
    # and the `end_line_diagnostic` is always the precise one
    extract_line = fn
      %Result{position: {line, _column}} -> line
      %Result{position: {start_line, _start_col, _end_line, _end_col}} -> start_line
      %Result{position: line} -> line
    end

    # Note: Sometimes error and warning appear on one line at the same time
    # So we need to uniq by line and severity,
    # and :error is always more important than :warning
    extract_line_and_severity = &{extract_line.(&1), &1.severity}

    diagnostics
    |> Enum.sort_by(extract_line_and_severity)
    |> Enum.uniq_by(extract_line)
    |> reject_zero_line()
  end

  # Parse errors happen during Code.string_to_quoted and are raised as SyntaxErrors, and TokenMissingErrors.
  def parse_error_to_diagnostics(
        %Document{} = source,
        context,
        {_error, detail} = message_info,
        token
      )
      when is_binary(detail) do
    detail_diagnostics = detail_diagnostics(source, detail)
    error = message_info_to_binary(message_info, token)
    error_diagnostics = parse_error_to_diagnostics(source, context, error, token)
    uniq(error_diagnostics ++ detail_diagnostics)
  end

  def parse_error_to_diagnostics(%Document{} = source, context, message_info, token)
      when is_exception(message_info) do
    parse_error_to_diagnostics(source, context, Exception.message(message_info), token)
  end

  def parse_error_to_diagnostics(%Document{} = source, context, message_info, token) do
    parse_error_diagnostic_functions = [
      &build_end_line_diagnostics/4,
      &build_start_line_diagnostics/4,
      &build_hint_diagnostics/4
    ]

    Enum.flat_map(
      parse_error_diagnostic_functions,
      & &1.(source, context, message_info, token)
    )
  end

  defp build_end_line_diagnostics(%Document{} = source, context, message_info, token) do
    [end_line_message | _] = String.split(message_info, "\n")

    message =
      if String.ends_with?(end_line_message, token) do
        end_line_message
      else
        end_line_message <> token
      end

    diagnostic = Result.new(source.uri, context_to_position(context), message, :error, "Elixir")
    [diagnostic]
  end

  @start_line_regex ~r/(\w+) \(for (.*) starting at line (\d+)\)/
  defp build_start_line_diagnostics(%Document{} = source, _context, message_info, _token) do
    case Regex.run(@start_line_regex, message_info) do
      [_, missing, token, start_line] ->
        message = "The #{token} here is missing a terminator: #{inspect(missing)}"
        position = String.to_integer(start_line)
        result = Result.new(source.uri, position, message, :error, @elixir_source)
        [result]

      _ ->
        []
    end
  end

  @hint_regex ~r/HINT: .*on line (\d+).*/m
  defp build_hint_diagnostics(%Document{} = source, _context, message_info, _token) do
    case Regex.run(@hint_regex, message_info) do
      [message, hint_line] ->
        message = String.replace(message, ~r/on line \d+/, "here")
        position = String.to_integer(hint_line)
        result = Result.new(source.uri, position, message, :error, @elixir_source)
        [result]

      _ ->
        []
    end
  end

  @doc """
  The `diagnostics_from_mix/2` is only for Elixir version > 1.15

  From 1.15 onwards with_diagnostics can return some compile-time errors,
  more details: https://github.com/elixir-lang/elixir/pull/12742
  """
  def diagnostics_from_mix(%Document{} = doc, all_errors_and_warnings)
      when is_list(all_errors_and_warnings) do
    for error_or_wanning <- all_errors_and_warnings do
      %{position: position, message: message, severity: severity} = error_or_wanning
      Result.new(doc.uri, position, message, severity, @elixir_source)
    end
  end

  def error_to_diagnostic(
        %Document{} = source,
        %CompileError{} = compile_error,
        _stack,
        _quoted_ast
      ) do
    path = compile_error.file || source.path

    Result.new(
      path,
      position(compile_error.line),
      compile_error.description,
      :error,
      @elixir_source
    )
  end

  def error_to_diagnostic(
        %Document{} = source,
        %FunctionClauseError{} = function_clause,
        stack,
        _quoted_ast
      ) do
    [{_module, _function, _arity, context} | _] = stack
    message = Exception.message(function_clause)
    position = context_to_position(context)
    Result.new(source.uri, position, message, :error, @elixir_source)
  end

  def error_to_diagnostic(
        %Document{} = source,
        %Mix.Error{} = error,
        _stack,
        _quoted_ast
      ) do
    message = Exception.message(error)
    position = position(1)
    Result.new(source.uri, position, message, :error, @elixir_source)
  end

  def error_to_diagnostic(
        %Document{} = source,
        %UndefinedFunctionError{} = undefined_function,
        stack,
        quoted_ast
      ) do
    [{module, function, arguments, context} | _] = stack
    message = Exception.message(undefined_function)

    position =
      if context == [] do
        arity = length(arguments)
        mfa = {module, function, arity}
        mfa_to_position(mfa, quoted_ast)
      else
        stack_to_position(stack)
      end

    Result.new(source.uri, position, message, :error, @elixir_source)
  end

  def error_to_diagnostic(
        %Document{} = source,
        %RuntimeError{} = runtime_error,
        _stack,
        _quoted_ast
      ) do
    message = Exception.message(runtime_error)
    position = 1
    Result.new(source.uri, position, message, :error, @elixir_source)
  end

  def error_to_diagnostic(
        %Document{} = source,
        %ArgumentError{} = argument_error,
        stack,
        _quoted_ast
      ) do
    reversed_stack = Enum.reverse(stack)

    [{_, _, _, context}, {_, call, _, second_to_last_context} | _] = reversed_stack

    pipe_or_struct? = call in [:|>, :__struct__]
    expanding_macro? = second_to_last_context[:file] == ~c"expanding macro"
    message = Exception.message(argument_error)

    position =
      if pipe_or_struct? or expanding_macro? do
        context_to_position(context)
      else
        stack_to_position(stack)
      end

    Result.new(source.uri, position, message, :error, @elixir_source)
  end

  def error_to_diagnostic(%Document{} = source, %module{} = exception, stack, _quoted_ast)
      when module in [
             Protocol.UndefinedError,
             ExUnit.DuplicateTestError,
             ExUnit.DuplicateDescribeError
           ] do
    message = Exception.message(exception)
    position = stack_to_position(stack)
    Result.new(source.uri, position, message, :error, @elixir_source)
  end

  def message_to_diagnostic(%Document{} = document, message_string) do
    message_string
    |> extract_individual_messages()
    |> Enum.map(&do_message_to_diagnostic(document, &1))
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

  defp do_message_to_diagnostic(_, "") do
    nil
  end

  defp do_message_to_diagnostic(_, "warning: redefining module" <> _) do
    nil
  end

  defp do_message_to_diagnostic(%Document{} = document, message) do
    message_lines = String.split(message, "\n")

    with {:ok, location_line} <- find_location(message_lines),
         {:ok, {file, line, mfa}} <- parse_location(location_line) do
      file =
        if blank?(file) do
          document.path
        else
          file
        end

      Result.new(file, line, message, :warning, @elixir_source, mfa)
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
    lines
    |> Enum.find(fn
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
  defp detail_diagnostics(%Document{} = source, detail) do
    case Regex.scan(@detail_location_re, detail) do
      [[matched, line_number]] ->
        line_number = String.to_integer(line_number)
        message = String.replace(detail, matched, "here")
        result = Result.new(source.uri, line_number, message, :error, @elixir_source)
        [result]

      _ ->
        []
    end
  end

  defp blank?(s) when is_binary(s) do
    String.trim(s) == ""
  end
end
