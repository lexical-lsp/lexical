defmodule Lexical.Enhancement do
  @enforce_keys [:project, :type, :validate, :enhance, :source]

  defstruct project: nil, uri: nil, type: nil, validate: nil, enhance: nil, source: nil

  def new(fields) do
    struct!(__MODULE__, fields)
  end
end
