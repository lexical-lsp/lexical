defmodule Lexical.RemoteControl.Search.Store.Backends.Khepri.Condition do
  @moduledoc """
  This module pulls in records Khepri uses to build path conditions.

  See here: https://hexdocs.pm/khepri/khepri_condition.html
  """
  require Record

  for {name, fields} <- Record.extract_all(from_lib: "khepri/include/khepri.hrl") do
    Record.defrecord(name, fields)
  end
end
