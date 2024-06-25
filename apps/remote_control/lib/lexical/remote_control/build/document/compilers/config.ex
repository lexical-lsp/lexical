defmodule Lexical.RemoteControl.Build.Document.Compilers.Config do
  @moduledoc """
  A compiler for elixir configuration
  """
  alias Elixir.Features
  alias Lexical.Document
  alias Lexical.Plugin.V1.Diagnostic
  alias Lexical.RemoteControl.Build

  @behaviour Build.Document.Compiler
  require Logger

  @impl true
  def enabled?, do: true

  @impl true
  def recognizes?(%Document{} = document) do
    in_config_dir? =
      document.path
      |> Path.dirname()
      |> String.starts_with?(config_dir())

    in_config_dir? and Path.extname(document.path) == ".exs"
  end

  @impl true
  def compile(%Document{} = document) do
    if Features.with_diagnostics?() do
      compile_with_diagnostics(document)
    else
      raw_compile(document)
    end
  end

  defp config_dir do
    # This function is called inside a call to `in_project` so we can
    # call Mix.Project.config() directly
    Mix.Project.config()
    |> Keyword.get(:config_path)
    |> Path.expand()
    |> Path.dirname()
  end

  defp raw_compile(%Document{} = document) do
    contents = Document.to_string(document)

    try do
      Config.Reader.eval!(document.path, contents, env: :test)
      {:ok, []}
    rescue
      e ->
        {:error, [to_result(document, e)]}
    end
  end

  defp compile_with_diagnostics(%Document{} = document) do
    {result, diagnostics} =
      apply(Code, :with_diagnostics, [
        # credo:disable-for-previous-line
        fn ->
          raw_compile(document)
        end
      ])

    diagnostic_results = Enum.map(diagnostics, &to_result(document, &1))

    case result do
      {:error, errors} ->
        {:error, reject_logged_messages(errors ++ diagnostic_results)}

      _ ->
        {:ok, reject_logged_messages(diagnostic_results)}
    end
  end

  defp to_result(%Document{} = document, %CompileError{} = error) do
    Diagnostic.Result.new(document.uri, error.line, Exception.message(error), :error, "Elixir")
  end

  defp to_result(%Document{} = document, %error_type{} = error)
       when error_type in [SyntaxError, TokenMissingError] do
    Diagnostic.Result.new(
      document.uri,
      {error.line, error.column},
      Exception.message(error),
      :error,
      "Elixir"
    )
  end

  defp to_result(%Document{} = document, %{
         position: position,
         message: message,
         severity: severity
       }) do
    Diagnostic.Result.new(
      document.path,
      position,
      message,
      severity,
      "Elixir"
    )
  end

  defp reject_logged_messages(results) do
    Enum.reject(results, &(&1.message =~ "have been logged"))
  end
end
