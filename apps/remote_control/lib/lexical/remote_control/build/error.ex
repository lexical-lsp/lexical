defmodule Lexical.RemoteControl.Build.Error do
  alias Mix.Task.Compiler.Diagnostic

  def error_to_diagnostic(%SyntaxError{} = syntax_error) do
    %Diagnostic{
      message: syntax_error.description,
      position: lsp_position(syntax_error.line, syntax_error.column),
      compiler_name: "Elixir",
      file: syntax_error.file,
      severity: :error
    }
  end

  def error_to_diagnostic(%TokenMissingError{} = token_error) do
    %Diagnostic{
      message: token_error.description,
      position: lsp_position(token_error.line, token_error.column),
      compiler_name: "Elixir",
      file: token_error.file,
      severity: :error
    }
  end

  def error_to_diagnostic(%CompileError{} = compile_error) do
    %Diagnostic{
      message: compile_error.description,
      position: lsp_position(compile_error.line, 0),
      compiler_name: "Elixir",
      file: compile_error.file,
      severity: :error
    }
  end

  def error_to_diagnostic(%FunctionClauseError{} = function_clause) do
    %Diagnostic{
      message: Exception.message(function_clause),
      position: lsp_position(0, 0),
      file: nil,
      severity: :error,
      compiler_name: "Elixir"
    }
  end

  def message_to_diagnostic(message_string) do
    message_string
    |> String.split("\n\n")
    |> Enum.map(&do_message_to_diagnostic/1)
    |> Enum.reject(&is_nil/1)
  end

  defp do_message_to_diagnostic("") do
    nil
  end

  defp do_message_to_diagnostic("redefining module" <> _) do
    nil
  end

  defp do_message_to_diagnostic(message) do
    [message, location] = String.split(message, "\n")

    case parse_location(location) do
      {:ok, location} ->
        {file, line, column, mfa} = location

        %Diagnostic{
          compiler_name: "Elixir",
          details: mfa,
          message: message,
          file: file,
          position: lsp_position(line, column),
          severity: :warning
        }

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

  defp lsp_position(line, column) do
    {max(0, line - 1), max(0, column - 1)}
  end
end
