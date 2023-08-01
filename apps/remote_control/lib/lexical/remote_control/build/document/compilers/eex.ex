defmodule Lexical.RemoteControl.Build.Document.Compilers.EEx do
  @moduledoc """
  A compiler for .eex files
  """
  alias Lexical.Document
  alias Lexical.Plugin.V1.Diagnostic.Result
  alias Lexical.RemoteControl.Build.Document.Compiler
  alias Lexical.RemoteControl.Build.Document.Compilers

  @behaviour Compiler

  def recognizes?(%Document{} = document) do
    Path.extname(document.path) == ".eex"
  end

  def enabled? do
    true
  end

  def compile(%Document{} = document) do
    with {:ok, quoted} <- eex_to_quoted(document) do
      Compilers.Quoted.compile(document, quoted, "EEx")
    end
  end

  defp eex_to_quoted(%Document{} = document) do
    try do
      quoted =
        document
        |> Document.to_string()
        |> EEx.compile_string(file: document.path)

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
end
