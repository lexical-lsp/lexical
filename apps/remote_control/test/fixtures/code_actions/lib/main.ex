defmodule Main do
  alias Remote.A.B, as: JustRemote
  alias Remote.A.B.C

  def wrong_remote_calls do
    Remote.A.B.C.fun()
    [JustRemote.C.fun(), B.C.fun(), C.fun()]
  end

  def wrong_remote_captures do
    [&Remote.A.B.C.fun/0, &JustRemote.C.fun/0, &B.C.fun/0, &C.fun/0]
  end
end
