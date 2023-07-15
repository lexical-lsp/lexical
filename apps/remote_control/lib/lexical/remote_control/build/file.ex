defmodule Lexical.RemoteControl.Build.File do
  alias Lexical.Document
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.ModuleMappings

  import Lexical.RemoteControl.Build.CaptureIO, only: [capture_io: 2]

  def compile(%Document{} = document) do
    case to_quoted(document) do
      {:ok, quoted} ->
        prepare_compile(document.path)

        if Version.match?(System.version(), "~> 1.15") do
          do_compile(quoted, document)
        else
          do_compile_and_capture_io(quoted, document)
        end

      {:error, {meta, message_info, token}} ->
        diagnostics = Build.Error.parse_error_to_diagnostics(document, meta, message_info, token)
        {:error, diagnostics}
    end
  end

  defp to_quoted(document) do
    source_string = Document.to_string(document)
    parser_options = [file: document.path] ++ parser_options()
    Code.put_compiler_option(:ignore_module_conflict, true)
    Code.string_to_quoted(source_string, parser_options)
  end

  defp do_compile(quoted_ast, document) do
    old_modules = ModuleMappings.modules_in_file(document.path)

    case compile_quoted_with_diagnostics(quoted_ast, document.path) do
      {{:ok, modules}, []} ->
        purge_removed_modules(old_modules, modules)
        {:ok, []}

      {{:ok, modules}, all_errors_and_warnings} ->
        purge_removed_modules(old_modules, modules)

        diagnostics =
          document
          |> Build.Error.diagnostics_from_mix(all_errors_and_warnings)
          |> Build.Error.refine_diagnostics()

        {:ok, diagnostics}

      {{:exception, exception, stack, quoted_ast}, all_errors_and_warnings} ->
        converted = Build.Error.error_to_diagnostic(document, exception, stack, quoted_ast)
        maybe_diagnostics = Build.Error.diagnostics_from_mix(document, all_errors_and_warnings)

        diagnostics =
          [converted | maybe_diagnostics]
          |> Enum.reverse()
          |> Build.Error.refine_diagnostics()

        {:error, diagnostics}
    end
  end

  defp do_compile_and_capture_io(quoted_ast, document) do
    # credo:disable-for-next-line Credo.Check.Design.TagTODO
    # TODO: remove this function once we drop support for Elixir 1.14
    old_modules = ModuleMappings.modules_in_file(document.path)
    compile = fn -> safe_compile_quoted(quoted_ast, document.path) end

    case capture_io(:stderr, compile) do
      {captured_messages, {:error, {:exception, {exception, _inner_stack}, stack}}} ->
        error = Build.Error.error_to_diagnostic(document, exception, stack, [])
        diagnostics = Build.Error.message_to_diagnostic(document, captured_messages)

        {:error, [error | diagnostics]}

      {captured_messages, {:exception, exception, stack, quoted_ast}} ->
        error = Build.Error.error_to_diagnostic(document, exception, stack, quoted_ast)
        diagnostics = Build.Error.message_to_diagnostic(document, captured_messages)

        {:error, [error | diagnostics]}

      {"", {:ok, modules}} ->
        purge_removed_modules(old_modules, modules)
        {:ok, []}

      {captured_warnings, {:ok, modules}} ->
        purge_removed_modules(old_modules, modules)
        diagnostics = Build.Error.message_to_diagnostic(document, captured_warnings)
        {:ok, diagnostics}
    end
  end

  defp prepare_compile(path) do
    # If we're compiling a mix.exs file, the after compile callback from
    # `use Mix.Project` will blow up if we add the same project to the project stack
    # twice. Preemptively popping it prevents that error from occurring.
    if Path.basename(path) == "mix.exs" do
      Mix.ProjectStack.pop()
    end

    Mix.Task.run(:loadconfig)
  end

  @dialyzer {:nowarn_function, compile_quoted_with_diagnostics: 2}

  defp compile_quoted_with_diagnostics(quoted_ast, path) do
    Code.with_diagnostics(fn ->
      safe_compile_quoted(quoted_ast, path)
    end)
  end

  defp safe_compile_quoted(quoted_ast, path) do
    try do
      {:ok, Code.compile_quoted(quoted_ast, path)}
    rescue
      exception ->
        {filled_exception, stack} = Exception.blame(:error, exception, __STACKTRACE__)
        {:exception, filled_exception, stack, quoted_ast}
    end
  end

  defp purge_removed_modules(old_modules, new_modules) do
    new_modules = MapSet.new(new_modules, fn {module, _bytecode} -> module end)
    old_modules = MapSet.new(old_modules)

    old_modules
    |> MapSet.difference(new_modules)
    |> Enum.each(fn to_remove ->
      :code.purge(to_remove)
      :code.delete(to_remove)
    end)
  end

  defp parser_options do
    [columns: true, token_metadata: true]
  end
end
