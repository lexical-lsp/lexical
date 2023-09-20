alias Lexical.RemoteControl.Search.Store.Mnesia

Mnesia.set_persist_to_disc(false)

{"", 0} = System.cmd("epmd", ~w(-daemon))
random_number = :rand.uniform(500)
{:ok, _pid} = :net_kernel.start([:"testing-#{random_number}@127.0.0.1"])

ExUnit.start(exclude: [:skip])
