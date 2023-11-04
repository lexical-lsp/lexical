defmodule Lexical.RemoteControl.Build.Document.Compilers.HEEx do
  @moduledoc """
  A compiler for .heex files
  """
  alias Lexical.Document
  alias Lexical.Plugin.V1.Diagnostic.Result
  alias Lexical.RemoteControl.Build.Document.Compiler
  alias Lexical.RemoteControl.Build.Document.Compilers
  require Logger

  @behaviour Compiler

  def recognizes?(%Document{} = document) do
    Path.extname(document.path) == ".heex"
  end

  def enabled? do
    true
  end

  def compile(%Document{} = document) do
    with {:ok, quoted} <- heex_to_quoted(document),
         :ok <- Compilers.EEx.eval_quoted(document, quoted) do
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

  defp error_to_result(%Document{} = document, %EEx.SyntaxError{} = error) do
    position = {error.line, error.column}

    Result.new(document.uri, position, error.message, :error, "EEx")
  end

  defp error_to_result(document, %error_struct{} = error)
       when error_struct in [
              TokenMissingError,
              Phoenix.LiveView.Tokenizer.ParseError
            ] do
    position = {error.line, error.column}
    Result.new(document.uri, position, error.description, :error, "HEEx")
  end
end
