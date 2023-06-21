defmodule Lexical.Plugin.V1.Diagnostic do
  @moduledoc """
  A use-able diagnostic plugin module

  A diagnostic result examines a `diagnosable` data structure and emits
  a list of `Lexical.Plugin.V1.Diagnostic.Result` structs.

  Diagnostic plugins are called in two places. When a file is saved, they're called with the
  `Lexical.Project` struct and are expected to perform diagnostics across the whole project.

  On receipt of a change to a `Lexical.Document`, they're called with the changed document and
  are expected to analyze that document and emit any diagnostics they find.

  Both calls to `diagnose` operate on tight deadlines, though when `diagnose` is called with a `Lexical.Project`,
  the deadline is much longer than it is when `diagnose` is called with a `Lexical.Document`. This is because
  analyzing a project should take a lot longer than analyzing a single document. Currently, Lexical sets
  a deadline of around a second on project-level diagnostics and a tens-of-milliseconds deadline on document
  plugins.


  ## Errors and Timeouts
  Plugins are very sensitive to errors and are disabled by lexical if they cause too many. At present,
  a disabled plugin can only be re-enabled by restarting lexical, so ensure that your plugin doesn't crash,
  and if you don't have diagnostics, return `{:ok, []}` rather than some error response.

  ## Plugin lifecycle

  When a plugin is started, Lexical calls the `init/0` function, which can perform setup actions, like starting
  the application associated with the plugin. Implementing this function is optional.
  From then on, the plugin will be resident and run in tasks whenever files are changed or saved.

  ## A simple do-nothing plugin

  ```
  defmodule DoesNothing do
    use Lexical.Plugin.V1.Diagnostic

    def diagnose(%Lexical.Document{} = doc) do
     {:ok, []}
    end

    def diagnose(%Lexical.Project{}) do
      {:ok, []}
    end
  end
  ```
  Check out the README for a plugin that does something more.
  """
  alias Lexical.Document
  alias Lexical.Plugin.V1.Diagnostic
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
