defmodule Lexical.RemoteControl.Search.Indexer.Entry do
  @type entry_type :: :module | :function | :macro | :field
  @type indexer :: :beam | :source
  @type subtype :: :reference | :definition
  @type line :: non_neg_integer()
  @type column :: non_neg_integer
  @type position :: {line, column}
  @type version :: String.t()
  @type entry_reference :: reference() | nil

  defstruct [
    :elixir_version,
    :erlang_version,
    :finish,
    :indexer,
    :updated_at,
    :subject,
    :parent,
    :path,
    :ref,
    :start,
    :subtype,
    :tokens,
    :type
  ]

  @type t :: %__MODULE__{
          elixir_version: version(),
          erlang_version: version(),
          finish: position(),
          indexer: indexer(),
          subject: String.t(),
          tokens: [String.t()],
          parent: entry_reference(),
          path: Path.t(),
          ref: entry_reference(),
          start: position(),
          subtype: subtype(),
          type: entry_type(),
          updated_at: pos_integer()
        }

  alias Lexical.VM.Versions

  def reference(
        path,
        ref,
        parent,
        subject,
        type,
        start,
        finish,
        tokenizer \\ &Function.identity/1
      )

  def reference(path, ref, parent, subject, type, start, finish, tokenizer) do
    versions = Versions.current()

    %__MODULE__{
      elixir_version: versions.elixir,
      erlang_version: versions.erlang,
      finish: finish,
      subject: subject,
      parent: parent,
      path: path,
      ref: ref,
      start: start,
      subtype: :reference,
      tokens: tokenizer.(subject),
      type: type,
      updated_at: timestamp()
    }
  end

  def definition(
        path,
        ref,
        parent,
        subject,
        type,
        start,
        finish,
        tokenizer \\ &Function.identity/1
      )

  def definition(path, ref, parent, subject, type, start, finish, tokenizer) do
    versions = Versions.current()

    %__MODULE__{
      elixir_version: versions.elixir,
      erlang_version: versions.erlang,
      finish: finish,
      subject: subject,
      parent: parent,
      path: path,
      ref: ref,
      start: start,
      subtype: :definition,
      tokens: tokenizer.(subject),
      type: type,
      updated_at: timestamp()
    }
  end

  defp timestamp do
    System.system_time(:millisecond)
  end
end
