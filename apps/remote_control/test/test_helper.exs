alias Lexical.RemoteControl.Search.Store
alias Lexical.RemoteControl.Search.Store.Mnesia
Store.set_backend(Store.Ets)
Mnesia.set_persist_to_disc(false)
random_number = :rand.uniform(500)
Node.start(:"testing-#{random_number}@127.0.0.1")
ExUnit.start(exclude: [:skip])
