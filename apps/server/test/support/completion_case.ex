defmodule Lexical.Test.Server.CompletionCase do
  use ExUnit.CaseTemplate

  alias Lexical.Project
  alias Lexical.Protocol.Types.Completion.Context, as: CompletionContext
  alias Lexical.RemoteControl
  alias Lexical.Server
  alias Lexical.Server.CodeIntelligence.Completion
  alias Lexical.Server.Project.Dispatch
  alias Lexical.SourceFile
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

  def complete(project, text, trigger_character \\ nil) do
    {line, column} = cursor_position(text)

    text = strip_cursor(text)

    root_path = Project.root_path(project)
    file_path = Path.join([root_path, "lib", "file.ex"])

    document =
      file_path
      |> SourceFile.Path.ensure_uri()
      |> SourceFile.new(text, 0)

    position = %SourceFile.Position{line: line, character: column}

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

    case Enum.filter(completions, matcher) do
      [] -> {:error, :not_found}
      [found] -> {:ok, found}
      found when is_list(found) -> {:ok, found}
    end
  end
end
