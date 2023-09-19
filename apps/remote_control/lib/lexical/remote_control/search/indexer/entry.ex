defmodule Lexical.RemoteControl.Search.Indexer.Entry do
  @type entry_type :: :module
  @type subject :: String.t()
  @type entry_subtype :: :reference | :definition
  @type version :: String.t()
  @type entry_reference :: reference() | nil

  defstruct [
    :application,
    :elixir_version,
    :erlang_version,
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
          elixir_version: version(),
          erlang_version: version(),
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
  alias Lexical.VM.Versions

  use StructAccess

  def reference(path, ref, parent, subject, type, range, application) do
    new(path, ref, parent, subject, type, :reference, range, application)
  end

  def definition(path, ref, parent, subject, type, range, application) do
    new(path, ref, parent, subject, type, :definition, range, application)
  end

  defp new(path, ref, parent, subject, type, subtype, range, application) do
    versions = Versions.current()

    %__MODULE__{
      application: application,
      elixir_version: versions.elixir,
      erlang_version: versions.erlang,
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
