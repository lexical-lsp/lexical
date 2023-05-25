defmodule Lexical.Plugin.Diagnostic.Result do
  defstruct [:location, :message, :severity, :source, :uri]

  @type severity :: :warning | :error
  @type t :: %__MODULE__{
          location: Lexical.Document.Range.t() | Lexical.Document.Position.t(),
          message: iodata(),
          severity: severity(),
          source: String.t(),
          uri: Lexical.uri()
        }

  def new(uri, location, message, severity, source) do
    %__MODULE__{
      uri: uri,
      location: location,
      message: message,
      source: source,
      severity: severity
    }
  end
end
