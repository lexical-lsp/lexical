defmodule Lexical.RemoteControl.Module.Loader do
  @moduledoc """
  Apparently, Code.ensure_loaded?/1 is pretty slow. I'm guessing because it has to do a
  round trip to the code server for each check. This in turn slows down indexing, so the thought
  is that having a cache will improve performance
  """

  alias Future.Code
  use Agent

  def start_link(_) do
    initialize = fn ->
      Map.new(:code.all_loaded(), fn {name, _} -> {:module, name} end)
    end

    Agent.start_link(initialize, name: __MODULE__)
  end

  def ensure_loaded(module_name) do
    Agent.get_and_update(__MODULE__, fn
      %{^module_name => result} = state ->
        {result, state}

      state ->
        result = Code.ensure_loaded(module_name)
        {result, Map.put(state, module_name, result)}
    end)
  end

  def ensure_loaded?(module_name) do
    match?({:module, ^module_name}, ensure_loaded(module_name))
  end

  def loaded?(module_name) do
    Agent.get(__MODULE__, fn
      %{^module_name => {:module, _}} ->
        true

      _ ->
        false
    end)
  end
end
