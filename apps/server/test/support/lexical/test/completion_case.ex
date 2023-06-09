defmodule Lexical.Test.Server.CompletionCase do
  alias Lexical.Document
  alias Lexical.Project
  alias Lexical.Protocol.Types.Completion.Context, as: CompletionContext
  alias Lexical.Protocol.Types.Completion.Item, as: CompletionItem
  alias Lexical.Protocol.Types.Completion.List, as: CompletionList
  alias Lexical.RemoteControl
  alias Lexical.Server
  alias Lexical.Server.CodeIntelligence.Completion
  alias Lexical.Server.Project.Dispatch
  alias Lexical.Test.CodeSigil

  use ExUnit.CaseTemplate
  import Lexical.Test.CursorSupport
  import Lexical.Test.Fixtures
  import RemoteControl.Api.Messages

  setup_all do
    project = project()

    {:ok, _} =
      start_supervised(
        {DynamicSupervisor, name: Server.Project.Supervisor.dynamic_supervisor_name()}
      )

    {:ok, _} = start_supervised({Server.Project.Supervisor, project})
    Dispatch.register(project, [project_compiled()])
    RemoteControl.Api.schedule_compile(project, true)
    assert_receive project_compiled(), 5000
    {:ok, project: project}
  end

  using do
    quote do
      import unquote(__MODULE__)
      import unquote(CodeSigil), only: [sigil_q: 2]
    end
  end

  def apply_completion(%CompletionItem{text_edit: %Document.Changes{} = changes}) do
    edits = List.wrap(changes.edits)
    {:ok, edited_document} = Document.apply_content_changes(changes.document, 1, edits)
    Document.to_string(edited_document)
  end

  def complete(project, text, trigger_character \\ nil) do
    {line, column} = cursor_position(text)

    text = strip_cursor(text)

    root_path = Project.root_path(project)
    file_path = Path.join([root_path, "lib", "file.ex"])

    document =
      file_path
      |> Document.Path.ensure_uri()
      |> Document.new(text, 0)

    position = %Document.Position{line: line, character: column}

    context =
      if is_binary(trigger_character) do
        CompletionContext.new(
          trigger_kind: :trigger_character,
          trigger_character: trigger_character
        )
      else
        CompletionContext.new(trigger_kind: :trigger_character)
      end

    Completion.complete(project, document, position, context)
  end

  def fetch_completion(completions, label_prefix) when is_binary(label_prefix) do
    case Enum.filter(completions, &String.starts_with?(&1.label, label_prefix)) do
      [] -> {:error, :not_found}
      [found] -> {:ok, found}
      found when is_list(found) -> {:ok, found}
    end
  end

  def fetch_completion(completions, opts) when is_list(opts) do
    matcher = fn completion ->
      Enum.reduce_while(opts, false, fn {key, value}, _ ->
        if Map.get(completion, key) == value do
          {:cont, true}
        else
          {:halt, false}
        end
      end)
    end

    completion_enumerable =
      case completions do
        %CompletionList{} = completion_list ->
          completion_list.items

        list when is_list(list) ->
          list
      end

    case Enum.filter(completion_enumerable, matcher) do
      [] -> {:error, :not_found}
      [found] -> {:ok, found}
      found when is_list(found) -> {:ok, found}
    end
  end

  def boosted?(%CompletionItem{} = item, expected_amount \\ :any) do
    case String.split(item.sort_text, "_") do
      [boost | _rest] ->
        actual_boost = String.to_integer(boost)

        if expected_amount == :any do
          actual_boost < 99
        else
          IO.puts("bost: #{99 - expected_amount}")
          actual_boost == 99 - expected_amount
        end

      _ ->
        false
    end
  end
end
