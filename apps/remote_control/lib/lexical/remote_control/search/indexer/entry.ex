defmodule Lexical.RemoteControl.Search.Indexer.Entry do
  @type entry_type :: :module
  @type subject :: String.t()
  @type entry_subtype :: :reference | :definition
  @type indexer :: :beam | :source
  @type line :: non_neg_integer()
  @type column :: non_neg_integer
  @type position :: {line, column}
  @type version :: String.t()
  @type entry_reference :: reference() | nil

  defstruct [
    :application,
    :elixir_version,
    :erlang_version,
    :indexer,
    :range,
    :updated_at,
    :subject,
    :parent,
    :path,
    :ref,
    :start,
    :subtype,
    :type
  ]

  @type t :: %__MODULE__{
          application: module(),
          elixir_version: version(),
          erlang_version: version(),
          indexer: indexer(),
          subject: subject(),
          parent: entry_reference(),
          path: Path.t(),
          range: Lexical.Document.Range.t(),
          ref: entry_reference(),
          subtype: entry_subtype(),
          type: entry_type(),
          updated_at: pos_integer()
        }

  alias Lexical.StructAccess
  alias Lexical.VM.Versions

  use StructAccess

  def reference(path, ref, parent, subject, type, range, application) do
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
      subtype: :reference,
      type: type,
      updated_at: timestamp()
    }
  end

  def definition(path, ref, parent, subject, type, range, application) do
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
      subtype: :definition,
      type: type,
      updated_at: timestamp()
    }
  end

  defp timestamp do
    System.system_time(:millisecond)
  end
end
