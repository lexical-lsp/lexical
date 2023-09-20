alias Lexical.RemoteControl.Search.Store

Store.Backends.Mnesia.set_persist_to_disc(false)
Store.set_backend(Store.Backends.Ets)
ExUnit.configure(timeout: :infinity)
ExUnit.start()
