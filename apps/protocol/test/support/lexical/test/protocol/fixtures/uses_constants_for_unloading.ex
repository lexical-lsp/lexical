defmodule Lexical.Test.Protocol.Fixtures.UsesConstantsForUnloading do
  alias Lexical.Proto
  alias Lexical.Test.Protocol.Fixtures.ConstantsForUnloading
  use Proto

  deftype name: string(), state: ConstantsForUnloading
end
