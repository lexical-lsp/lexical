defmodule Lexical.RemoteControl.Build.Error do
  alias Lexical.Document
  alias Lexical.Plugin.V1.Diagnostic.Result
  alias Lexical.RemoteControl.Build.Error.Location
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
    |> Location.uniq()
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

  @undefined_function_pattern ~r/ \(expected ([A-Za-z0-9_\.]*) to [^\)]+\)/

  defp format_message("undefined" <> _ = message) do
    # All undefined function messages explain the *same* thing inside the parentheses
    String.replace(message, @undefined_function_pattern, "")
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

  @doc """
  The `diagnostics_from_mix/2` is only for Elixir version > 1.15

  From 1.15 onwards `with_diagnostics` can return some compile-time errors,
  more details: https://github.com/elixir-lang/elixir/pull/12742
  """
  def diagnostics_from_mix(%Document{} = doc, all_errors_and_warnings)
      when is_list(all_errors_and_warnings) do
    for error_or_wanning <- all_errors_and_warnings do
      %{position: pos, message: message, severity: severity} = error_or_wanning

      position =
        if span = error_or_wanning[:span] do
          Location.range(doc, pos, span)
        else
          pos
        end

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
      Location.position(compile_error.line),
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
    position = Location.context_to_position(context)
    Result.new(source.uri, position, message, :error, @elixir_source)
  end

  def error_to_diagnostic(
        %Document{} = source,
        %Mix.Error{} = error,
        _stack,
        _quoted_ast
      ) do
    message = Exception.message(error)
    position = Location.position(1)
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
      if context == [] and is_list(arguments) do
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
        %error_struct{} = argument_error,
        stack,
        _quoted_ast
      )
      when error_struct in [ArgumentError, KeyError] do
    reversed_stack = Enum.reverse(stack)

    [{_, _, _, context}, {_, call, _, second_to_last_context} | _] = reversed_stack

    pipe_or_struct? = call in [:|>, :__struct__]
    expanding? = second_to_last_context[:file] in [~c"expanding macro", ~c"expanding struct"]
    message = Exception.message(argument_error)

    position =
      if pipe_or_struct? or expanding? do
        Location.context_to_position(context)
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
        Location.position(0)

      Keyword.has_key?(context, :line) and Keyword.has_key?(context, :column) ->
        Location.position(context[:line], context[:column])

      Keyword.has_key?(context, :line) ->
        Location.position(context[:line])

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
    Location.context_to_position(context)
  end

  defp stack_to_position([]) do
    nil
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

  defp blank?(s) when is_binary(s) do
    String.trim(s) == ""
  end
end
