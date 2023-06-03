defmodule Mix.Tasks.Namespace do
  def app_mappings do
    %{
      common: Lexical.Common,
      remote_control: Lexical.RemoteControl,
      lexical_shared: Lexical.Shared,
      lexical_plugin: Lexical.Plugin,
      sourceror: Sourceror,
      path_glob: PathGlob,
      server: Lexical.Server,
      protocol: Lexical.Protocol,
      proto: Proto
    }
  end

  def apps_to_namespace do
    Map.keys(app_mappings())
  end

  def root_modules do
    Map.values(app_mappings())
  end
end
