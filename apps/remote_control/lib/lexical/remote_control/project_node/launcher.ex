defmodule Lexical.RemoteControl.ProjectNode.Launcher do
  @moduledoc """
  A module that provides the path of an executable to launch another
  erlang node via ports.
  """
  def path do
    path(:os.type())
  end

  def path({:unix, _}) do
    with :non_existing <- :code.where_is_file(~c"port_wrapper.sh") do
      :remote_control
      |> :code.priv_dir()
      |> Path.join("port_wrapper.sh")
      |> Path.expand()
    end
    |> to_string()
  end
end
