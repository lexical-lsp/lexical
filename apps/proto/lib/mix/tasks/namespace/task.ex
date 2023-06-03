defmodule Mix.Tasks.Namespace.Task do
  def apps_to_namespace do
    ~w(remote_control common server protocol proto lexical_shared lexical_plugin sourceror path_glob)a
  end
end
