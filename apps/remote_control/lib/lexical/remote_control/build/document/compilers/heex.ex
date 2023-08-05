defmodule Lexical.RemoteControl.Build.Document.Compilers.HEEx do
  @moduledoc """
  A compiler for .heex files
  """
  alias Lexical.Document
  alias Lexical.Plugin.V1.Diagnostic.Result
  alias Lexical.RemoteControl.Build.Document.Compiler
  alias Lexical.RemoteControl.Build.Error
  require Logger

  @behaviour Compiler

  def recognizes?(%Document{} = document) do
    Path.extname(document.path) == ".heex"
  end

  def enabled? do
    true
  end

  def compile(%Document{} = document) do
    with {:ok, _quoted} <- heex_to_quoted(document),
         {:ok, _string} <- eval(document) do
      {:ok, []}
    end
  end

  defp heex_to_quoted(%Document{} = document) do
    try do
      source = Document.to_string(document)

      opts =
        [
          source: source,
          file: document.path,
          caller: __ENV__,
          engine: Phoenix.LiveView.TagEngine,
          subengine: Phoenix.LiveView.Engine,
          tag_handler: Phoenix.LiveView.HTMLEngine
        ]

      quoted = EEx.compile_string(source, opts)

      {:ok, quoted}
    rescue
      error ->
        {:error, [error_to_result(document, error)]}
    end
  end

  defp eval(%Document{} = document) do
    # Evaluating the Html.Engine compiled quoted doesn't report any errors,
    # so we need to use the original `EEx` to compile it to quoted and evaluate it.
    quoted_ast =
      document
      |> Document.to_string()
      |> EEx.compile_string(file: document.path)

    try do
      {result, _} = Code.eval_quoted(quoted_ast, [assigns: %{}], file: document.path)
      {:ok, result}
    rescue
      exception ->
        {filled_exception, stack} = Exception.blame(:error, exception, __STACKTRACE__)
        {:exception, filled_exception, stack, quoted_ast}

        error =
          [Error.error_to_diagnostic(document, exception, stack, quoted_ast)]
          |> Error.refine_diagnostics()

        {:error, error}
    end
  end

  defp error_to_result(document, %error_struct{} = error)
       when error_struct in [
              EEx.SystaxError,
              TokenMissingError,
              Phoenix.LiveView.Tokenizer.ParseError
            ] do
    position = {error.line, error.column}
    Result.new(document.uri, position, error.description, :error, "HEEx")
  end
end
