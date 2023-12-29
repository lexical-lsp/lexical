defmodule Lexical.RemoteControl.Search.Indexer.Entry do
  @type entry_type :: :module
  @type subject :: String.t()
  @type entry_subtype :: :reference | :definition
  @type version :: String.t()
  @type entry_reference :: reference() | nil

  defstruct [
    :application,
    :parent,
    :path,
    :range,
    :ref,
    :subject,
    :subtype,
    :type,
    :updated_at
  ]

  @type t :: %__MODULE__{
          application: module(),
          subject: subject(),
          parent: entry_reference(),
          path: Path.t(),
          range: Lexical.Document.Range.t(),
          ref: entry_reference(),
          subtype: entry_subtype(),
          type: entry_type(),
          updated_at: :calendar.datetime()
        }

  alias Lexical.StructAccess

  use StructAccess

  def reference(path, ref, parent, subject, type, range, application) do
    new(path, ref, parent, subject, type, :reference, range, application)
  end

  def definition(path, ref, parent, subject, type, range, application) do
    new(path, ref, parent, subject, type, :definition, range, application)
  end

  defp new(path, ref, parent, subject, type, subtype, range, application) do
    %__MODULE__{
      application: application,
      subject: subject,
      parent: parent,
      path: path,
      range: range,
      ref: ref,
      subtype: subtype,
      type: type,
      updated_at: timestamp()
    }
  end

  defp timestamp do
    :calendar.universal_time()
  end
end
