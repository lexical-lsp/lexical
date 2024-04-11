defmodule Lexical.RemoteControl.Search.Indexer.Entry do
  @type entry_type :: :module
  @type subject :: String.t()
  @type entry_subtype :: :reference | :definition
  @type version :: String.t()
  @type entry_id :: pos_integer() | nil
  @type block_id :: pos_integer() | :root

  defstruct [
    :application,
    :id,
    :block_id,
    :block_range,
    :path,
    :range,
    :subject,
    :subtype,
    :type
  ]

  @type t :: %__MODULE__{
          application: module(),
          subject: subject(),
          block_id: block_id(),
          block_range: Lexical.Document.Range.t() | nil,
          path: Path.t(),
          range: Lexical.Document.Range.t(),
          subtype: entry_subtype(),
          type: entry_type()
        }
  @type datetime_format :: :erl | :unix | :datetime
  @type date_type :: :calendar.datetime() | integer() | DateTime.t()

  alias Lexical.Identifier
  alias Lexical.RemoteControl.Search.Indexer.Source.Block
  alias Lexical.StructAccess

  use StructAccess

  defguard is_structure(entry) when entry.type == :metadata and entry.subtype == :block_structure
  defguard is_block(entry) when entry.id == entry.block_id

  @doc """
  Creates a new entry by copying the passed-in entry.

  The returned entry will have the same fields set as the one passed in,
  but a different id.
  You can also pass in a keyword list of overrides, which will overwrit values in
  the returned struct.
  """
  def copy(%__MODULE__{} = orig, overrides \\ []) when is_list(overrides) do
    %__MODULE__{orig | id: Identifier.next_global!()}
    |> struct(overrides)
  end

  def block_structure(path, structure) do
    %__MODULE__{
      path: path,
      subject: structure,
      type: :metadata,
      subtype: :block_structure
    }
  end

  def reference(path, %Block{} = block, subject, type, range, application) do
    new(path, Identifier.next_global!(), block.id, subject, type, :reference, range, application)
  end

  def definition(path, %Block{} = block, subject, type, range, application) do
    new(path, Identifier.next_global!(), block.id, subject, type, :definition, range, application)
  end

  def block_definition(
        path,
        %Block{} = block,
        subject,
        type,
        block_range,
        detail_range,
        application
      ) do
    definition =
      definition(
        path,
        block.id,
        block.parent_id,
        subject,
        type,
        detail_range,
        application
      )

    %__MODULE__{definition | block_range: block_range}
  end

  defp definition(path, id, block_id, subject, type, range, application) do
    new(path, id, block_id, subject, type, :definition, range, application)
  end

  defp new(path, id, block_id, subject, type, subtype, range, application) do
    %__MODULE__{
      application: application,
      block_id: block_id,
      id: id,
      path: path,
      range: range,
      subject: subject,
      subtype: subtype,
      type: type
    }
  end

  def block?(%__MODULE__{} = entry) do
    is_block(entry)
  end

  @spec updated_at(t()) :: date_type()
  @spec updated_at(t(), datetime_format) :: date_type()
  def updated_at(entry, format \\ :erl)

  def updated_at(%__MODULE__{id: id} = entry, format) when is_integer(id) do
    case format do
      :erl -> Identifier.to_erl(entry.id)
      :unix -> Identifier.to_unix(id)
      :datetime -> Identifier.to_datetime(id)
    end
  end

  def updated_at(%__MODULE__{}, _format) do
    nil
  end
end
