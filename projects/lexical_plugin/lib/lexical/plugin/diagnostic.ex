defmodule Lexical.Plugin.Diagnostic do
  alias Lexical.Document
  alias Lexical.Plugin.Diagnostic
  alias Lexical.Project

  @type state :: any()
  @type results :: [Diagnostic.Result.t()]

  @type diagnosable :: Project.t() | Document.t()
  @type diagnostics_reply :: {:ok, results} | {:error, any()}

  @callback handle(diagnosable) :: diagnostics_reply()

  defmacro __using__(opts) do
    name = Keyword.get(opts, :name)

    quote location: :keep do
      require Logger
      Module.register_attribute(__MODULE__, :lexical_plugin, persist: true)
      @lexical_plugin true
      @behaviour unquote(__MODULE__)

      def __lexical_plugin__ do
        __MODULE__
      end

      def __plugin_type__ do
        :diagnostic
      end

      def name do
        unquote(name)
      end

      def init do
        :ok
      end

      def handle(_) do
        {:ok, []}
      end

      defoverridable init: 0, handle: 1
    end
  end
end
