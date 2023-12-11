defmodule Lexical.RemoteControl.Build.ParseError do
  alias Lexical.Document
  alias Lexical.Plugin.V1.Diagnostic.Result

  import Lexical.RemoteControl.Build.ErrorSupport,
    only: [context_to_position: 1]

  @elixir_source "Elixir"

  # Parse errors happen during Code.string_to_quoted and are raised as SyntaxErrors, and TokenMissingErrors.
  def to_diagnostics(
        %Document{} = source,
        context,
        {_error, detail} = message_info,
        token
      )
      when is_binary(detail) do
    detail_diagnostics = detail_diagnostics(source, detail)
    error = message_info_to_binary(message_info, token)
    error_diagnostics = to_diagnostics(source, context, error, token)
    error_diagnostics ++ detail_diagnostics
  end

  def to_diagnostics(%Document{} = source, context, message_info, token)
      when is_exception(message_info) do
    to_diagnostics(source, context, Exception.message(message_info), token)
  end

  def to_diagnostics(%Document{} = source, context, message_info, token) do
    # We need to uniq by position because the same position can be reported
    # and the `end_line_diagnostic` is always the precise one
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
end
