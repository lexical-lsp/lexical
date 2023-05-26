defmodule Lexical.Plugin.Diagnostic do
  alias Lexical.Document
  alias Lexical.Plugin.Diagnostic

  @callback diagnose(Document.t()) :: [Diagnostic.Result.t()]

  defmacro __using__(_) do
    quote do
      Module.register_attribute(__MODULE__, :lexical_plugin, persist: true)

      @lexical_plugin true
      @behaviour Lexical.Plugin.Diagnostic

      def __lexical_plugin__ do
        __MODULE__
      end

      def __plugin_type__ do
        :diagnostic
      end

      def init do
        :ok
      end

      defoverridable init: 0
    end
  end
end
