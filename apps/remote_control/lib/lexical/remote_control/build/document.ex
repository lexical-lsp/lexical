defmodule Lexical.RemoteControl.Build.Document do
  alias Lexical.Document
  alias Lexical.RemoteControl.Build.Document.Compilers

  @compilers [Compilers.Config, Compilers.Elixir, Compilers.EEx, Compilers.HEEx, Compilers.NoOp]

  def compile(%Document{} = document) do
    compiler = Enum.find(@compilers, & &1.recognizes?(document))
    compiler.compile(document)
  end
end
