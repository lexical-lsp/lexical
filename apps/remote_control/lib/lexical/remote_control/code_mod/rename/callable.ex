defmodule Lexical.RemoteControl.CodeMod.Rename.Callable do
  alias Lexical.Ast
  alias Lexical.Ast.Analysis
  alias Lexical.Ast.Callable
  alias Lexical.Document
  alias Lexical.Document.Edit
  alias Lexical.Document.Position
  alias Lexical.Document.Range

  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.CodeIntelligence.Entity
  alias Lexical.RemoteControl.Search.Store
  alias Lexical.RemoteControl.Search.Subject

  require Sourceror.Identifier

  @spec resolve(Analysis.t(), Position.t()) ::
          {:ok, {atom(), String.t()}, Range.t()} | {:error, atom()}
  def resolve(%Analysis{} = analysis, %Position{} = position) do
    # `nil` means that the function from a script or a test file
    independent_apps = [nil | independent_apps()]

    with {:ok, {callable, module, local_name, _arity}, range} when callable in [:call] <-
           Entity.resolve(analysis, position),
         {:ok, name_range} <- Callable.fetch_name_range(analysis, range.start, local_name),
         true <- Application.get_application(module) in independent_apps do
      {:ok, {:call, {module, local_name}}, name_range}
    else
      _ ->
        {:error, :not_a_callable}
    end
  end

  def rename(%Range{} = _range, new_name, {module, local_name}) do
    mfa = Subject.mfa(module, local_name, "")

    results =
      for entry <- Store.prefix(mfa, []),
          result = adjust_range(entry, local_name),
          match?({:ok, _}, result) do
        {:ok, range} = result
        %{entry | range: range}
      end

    results
    |> Enum.uniq_by(& &1.range)
    |> Enum.group_by(
      &Document.Path.ensure_uri(&1.path),
      &Edit.new(new_name, &1.range)
    )
    |> Enum.flat_map(fn {uri, entries} ->
      case to_document_changes(uri, entries, new_name) do
        {:ok, document_changes} -> [document_changes]
        _ -> []
      end
    end)
  end

  defp adjust_range(entry, local_name) do
    uri = Document.Path.ensure_uri(entry.path)

    with {:ok, _} <- Document.Store.open_temporary(uri),
         {:ok, _document, analysis} <- Document.Store.fetch(uri, :analysis) do
      Ast.Callable.fetch_name_range(analysis, entry.range.start, local_name)
    end
  end

  defp to_document_changes(uri, entries, new_name) do
    edits = Enum.map(entries, &Edit.new(new_name, &1.range))

    with {:ok, document} <- Document.Store.fetch(uri) do
      {:ok, Document.Changes.new(document, edits, nil)}
    end
  end

  defp independent_apps do
    get_apps =
      fn _ ->
        if Mix.Project.umbrella?() do
          Map.keys(Mix.Project.apps_paths())
        else
          [Mix.Project.config()[:app]]
        end
      end

    case RemoteControl.Mix.in_project(get_apps) do
      {:ok, apps} -> apps
      _ -> []
    end
  end
end
