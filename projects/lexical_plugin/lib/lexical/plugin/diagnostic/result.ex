defmodule Lexical.Plugin.Diagnostic.Result do
  alias Lexical.Document
  defstruct [:details, :message, :position, :severity, :source, :uri]

  @type path_or_uri :: Lexical.path() | Lexical.uri()
  @type severity :: :message | :warning | :error
  @type mix_position ::
          non_neg_integer()
          | {pos_integer(), non_neg_integer()}
          | {pos_integer(), non_neg_integer(), pos_integer(), non_neg_integer()}

  @type position :: mix_position() | Document.Range.t() | Document.Position.t()
  @type t :: %__MODULE__{
          position: position,
          message: iodata(),
          severity: severity(),
          source: String.t(),
          uri: Lexical.uri()
        }

  @spec new(path_or_uri, position, iodata(), severity(), String.t()) :: t
  @spec new(path_or_uri, position, iodata(), severity(), String.t(), any()) :: t
  def new(maybe_uri_or_path, position, message, severity, source, details \\ nil) do
    uri =
      if maybe_uri_or_path do
        Document.Path.ensure_uri(maybe_uri_or_path)
      end

    message = IO.iodata_to_binary(message)

    %__MODULE__{
      uri: uri,
      position: position,
      message: message,
      source: source,
      severity: severity,
      details: details
    }
  end
end
