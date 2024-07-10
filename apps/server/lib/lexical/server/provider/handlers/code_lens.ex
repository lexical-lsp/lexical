defmodule Lexical.Server.Provider.Handlers.CodeLens do
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Document.Range
  alias Lexical.Project
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Responses
  alias Lexical.Protocol.Types.CodeLens
  alias Lexical.RemoteControl
  alias Lexical.Server.Configuration
  alias Lexical.Server.Provider.Handlers

  import Document.Line
  require Logger

  def handle(%Requests.CodeLens{} = request, %Configuration{} = config) do
    lenses =
      case reindex_lens(config.project, request.document) do
        nil -> []
        lens -> List.wrap(lens)
      end

    response = Responses.CodeLens.new(request.id, lenses)
    {:reply, response}
  end

  defp reindex_lens(%Project{} = project, %Document{} = document) do
    if show_reindex_lens?(project, document) do
      range = def_project_range(document)
      command = Handlers.Commands.reindex_command(project)

      CodeLens.new(command: command, range: range)
    end
  end

  @project_regex ~r/def\s+project\s/
  defp def_project_range(%Document{} = document) do
    # returns the line in mix.exs where `def project` occurs
    Enum.reduce_while(document.lines, nil, fn
      line(text: line_text, line_number: line_number), _ ->
        if String.match?(line_text, @project_regex) do
          start_pos = Position.new(document, line_number, 1)
          end_pos = Position.new(document, line_number, String.length(line_text))
          range = Range.new(start_pos, end_pos)
          {:halt, range}
        else
          {:cont, nil}
        end
    end)
  end

  defp show_reindex_lens?(%Project{} = project, %Document{} = document) do
    document_path = Path.expand(document.path)

    document_path == Project.mix_exs_path(project) and
      not RemoteControl.Api.index_running?(project)
  end
end
