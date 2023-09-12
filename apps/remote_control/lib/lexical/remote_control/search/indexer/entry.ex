defmodule Lexical.RemoteControl.Search.Indexer.Entry do
  alias Lexical.Document

  @type entry_type :: :module
  @type subject :: String.t()
  @type entry_subtype :: :reference | :definition
  @type line :: non_neg_integer()
  @type column :: non_neg_integer
  @type position :: {line, column}
  @type version :: String.t()
  @type entry_reference :: reference() | nil

  defstruct [
    :application,
    :elixir_version,
    :end_line,
    :erlang_version,
    :parent,
    :path,
    :range,
    :ref,
    :start_line,
    :subject,
    :subtype,
    :type,
    :updated_at
  ]

  @type t :: %__MODULE__{
          application: module(),
          elixir_version: version(),
          end_line: Document.Line.t(),
          erlang_version: version(),
          parent: entry_reference(),
          path: Path.t(),
          range: Document.Range.t(),
          ref: entry_reference(),
          start_line: Document.Line.t(),
          subject: subject(),
          subtype: entry_subtype(),
          type: entry_type(),
          updated_at: :calendar.datetime()
        }

  alias Lexical.StructAccess
  alias Lexical.VM.Versions

  use StructAccess

  def reference(%Document{} = document, ref, parent, subject, type, range, application) do
    new(document, ref, parent, subject, type, :reference, range, application)
  end

  def definition(%Document{} = document, ref, parent, subject, type, range, application) do
    new(document, ref, parent, subject, type, :definition, range, application)
  end

  defp new(%Document{} = document, ref, parent, subject, type, subtype, range, application) do
    versions = Versions.current()
    {:ok, start_line} = Document.fetch_line_at(document, range.start.line)
    {:ok, end_line} = Document.fetch_line_at(document, range.end.line)

    %__MODULE__{
      application: application,
      elixir_version: versions.elixir,
      end_line: end_line,
      erlang_version: versions.erlang,
      parent: parent,
      path: document.path,
      range: range,
      ref: ref,
      start_line: start_line,
      subject: subject,
      subtype: subtype,
      type: type,
      updated_at: timestamp()
    }
  end

  defp timestamp do
    :calendar.universal_time()
  end
end
