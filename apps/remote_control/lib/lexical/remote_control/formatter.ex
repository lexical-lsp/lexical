defmodule Lexical.RemoteControl.Formatter do
  alias Lexical.RemoteControl

  def for_file(path) do
    RemoteControl.in_mix_project(fn _ ->
      Mix.Tasks.Format.formatter_for_file(path)
    end)
  end

  def opts_for_file(path) do
    RemoteControl.in_mix_project(fn _ ->
      Mix.Tasks.Format.formatter_opts_for_file(path)
    end)
  end
end
