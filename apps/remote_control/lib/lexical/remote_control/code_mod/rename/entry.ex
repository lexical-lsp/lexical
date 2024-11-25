defmodule Lexical.RemoteControl.CodeMod.Rename.Entry do
  @moduledoc """
  """
  alias Lexical.RemoteControl.Search.Indexer, as: Indexer

  # When renaming, we rely on the `Indexer.Entry`,
  # and we also need some other fields used exclusively for renaming, such as `edit_range`.
  @type t :: %__MODULE__{
          id: Indexer.Entry.entry_id(),
          path: Lexical.path(),
          subject: Indexer.Entry.subject(),
          block_range: Lexical.Document.Range.t() | nil,
          range: Lexical.Document.Range.t(),
          edit_range: Lexical.Document.Range.t(),
          subtype: Indexer.Entry.entry_subtype()
        }
  defstruct [
    :id,
    :path,
    :subject,
    :block_range,
    :range,
    :edit_range,
    :subtype
  ]

  def new(%Indexer.Entry{} = indexer_entry) do
    %__MODULE__{
      id: indexer_entry.id,
      path: indexer_entry.path,
      subject: indexer_entry.subject,
      subtype: indexer_entry.subtype,
      block_range: indexer_entry.block_range,
      range: indexer_entry.range,
      edit_range: indexer_entry.range
    }
  end
end
