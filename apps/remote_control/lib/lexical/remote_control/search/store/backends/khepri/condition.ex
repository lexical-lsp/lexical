defmodule Lexical.RemoteControl.Search.Store.Backends.Khepri.Condition do
  require Record

  for {name, fields} <- Record.extract_all(from_lib: "khepri/include/khepri.hrl") do
    Record.defrecord(name, fields)
  end
end
