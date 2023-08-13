defmodule Lexical.RemoteControl.Build.Document.Compilers.HEEx do
  @moduledoc """
  A compiler for .heex files
  """
  alias Lexical.Document
  alias Lexical.Plugin.V1.Diagnostic.Result
  alias Lexical.RemoteControl.Build
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
    with {:ok, _quoted} <- heex_to_quoted(document),
         {:ok, eex_quoted_ast} <- eval(document) do
      compile_quoted(document, eex_quoted_ast)
    end
  end

  defp compile_quoted(%Document{} = document, quoted) do
    with {:error, errors} <- Compilers.Quoted.compile(document, quoted, "HEEx") do
      {:error, reject_undefined_assigns(errors)}
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

    result =
      if Elixir.Features.with_diagnostics?() do
        eval_quoted_with_diagnostics(quoted_ast, document.path)
      else
        eval_quoted(quoted_ast, document.path)
      end

    case result do
      {:ok, quoted_ast} ->
        {:ok, quoted_ast}

      {:exception, exception, stack} ->
        converted =
          document
          |> Build.Error.error_to_diagnostic(exception, stack, quoted_ast)
          |> Map.put(:source, "HEEx")

        {:error, [converted]}

      {{:ok, quoted_ast}, _} ->
        # Ignore warnings for now
        # because they will be handled by `compile_quoted/2`
        # like: `assign @thing not available in EEx template`
        {:ok, quoted_ast}

      {{:exception, exception, stack, quoted_ast}, all_errors_and_warnings} ->
        converted = Build.Error.error_to_diagnostic(document, exception, stack, quoted_ast)
        maybe_diagnostics = Build.Error.diagnostics_from_mix(document, all_errors_and_warnings)

        diagnostics =
          [converted | maybe_diagnostics]
          |> Enum.reverse()
          |> Build.Error.refine_diagnostics()
          |> Enum.map(&Map.replace!(&1, :source, "HEEx"))

        {:error, diagnostics}
    end
  end

  defp eval_quoted_with_diagnostics(quoted_ast, path) do
    # Using apply to prevent a compile warning on elixir < 1.15
    # credo:disable-for-next-line
    apply(Code, :with_diagnostics, [fn -> eval_quoted(quoted_ast, path) end])
  end

  def eval_quoted(quoted_ast, path) do
    try do
      {_, _} = Code.eval_quoted(quoted_ast, [assigns: %{}], file: path)
      {:ok, quoted_ast}
    rescue
      exception ->
        {filled_exception, stack} = Exception.blame(:error, exception, __STACKTRACE__)
        {:exception, filled_exception, stack, quoted_ast}
    end
  end

  defp reject_undefined_assigns(errors) do
    # NOTE: Ignoring error for assigns makes sense,
    # because we don't want such a error report,
    # for example: `<%= @name %>`
    Enum.reject(errors, fn %Result{message: message} ->
      message =~ ~s[undefined variable "assigns"]
    end)
  end

  defp error_to_result(%Document{} = document, %EEx.SyntaxError{} = error) do
    position = {error.line, error.column}

    Result.new(document.uri, position, error.message, :error, "HEEx")
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
