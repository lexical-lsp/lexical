defmodule Lexical.RemoteControl.Search.Indexer.Entry do
  @type entry_type :: :module
  @type subject :: String.t()
  @type entry_subtype :: :reference | :definition
  @type version :: String.t()
  @type entry_id :: pos_integer() | nil

  defstruct [
    :application,
    :id,
    :parent,
    :path,
    :range,
    :subject,
    :subtype,
    :type,
    :updated_at
  ]

  @type t :: %__MODULE__{
          application: module(),
          subject: subject(),
          parent: entry_id(),
          path: Path.t(),
          range: Lexical.Document.Range.t(),
          subtype: entry_subtype(),
          type: entry_type(),
          updated_at: :calendar.datetime()
        }

  alias Lexical.StructAccess

  use StructAccess

  def reference(path, id, parent, subject, type, range, application) do
    new(path, id, parent, subject, type, :reference, range, application)
  end

  def definition(path, id, parent, subject, type, range, application) do
    new(path, id, parent, subject, type, :definition, range, application)
  end

  defp new(path, id, parent, subject, type, subtype, range, application) do
    %__MODULE__{
      application: application,
      subject: subject,
      id: id,
      parent: parent,
      path: path,
      range: range,
      subtype: subtype,
      type: type,
      updated_at: timestamp()
    }
  end

  defp timestamp do
    :calendar.universal_time()
  end
end
