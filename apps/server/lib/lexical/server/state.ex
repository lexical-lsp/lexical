defmodule Lexical.Server.State do
  alias Lexical.Document
  alias Lexical.Protocol.Id
  alias Lexical.Protocol.Notifications.DidChange
  alias Lexical.Protocol.Notifications.DidChangeConfiguration
  alias Lexical.Protocol.Notifications.DidClose
  alias Lexical.Protocol.Notifications.DidOpen
  alias Lexical.Protocol.Notifications.DidSave
  alias Lexical.Protocol.Notifications.Exit
  alias Lexical.Protocol.Notifications.Initialized
  alias Lexical.Protocol.Requests.Initialize
  alias Lexical.Protocol.Requests.RegisterCapability
  alias Lexical.Protocol.Requests.Shutdown
  alias Lexical.Protocol.Responses
  alias Lexical.Protocol.Types
  alias Lexical.Protocol.Types.CodeAction
  alias Lexical.Protocol.Types.Completion
  alias Lexical.Protocol.Types.DidChangeWatchedFiles
  alias Lexical.Protocol.Types.FileSystemWatcher
  alias Lexical.Protocol.Types.Registration
  alias Lexical.Protocol.Types.TextDocument
  alias Lexical.RemoteControl.Api
  alias Lexical.Server.CodeIntelligence
  alias Lexical.Server.Configuration
  alias Lexical.Server.Project
  alias Lexical.Server.Transport
  alias Lexical.Throttler

  require CodeAction.Kind
  require Logger

  defstruct configuration: nil, initialized?: false, shutdown_received?: false

  @supported_code_actions [
    :quick_fix
  ]

  def new do
    %__MODULE__{}
  end

  def initialize(%__MODULE__{initialized?: false} = state, %Initialize{
        lsp: %Initialize.LSP{} = event
      }) do
    config = Configuration.new(event.root_uri, event.capabilities)
    new_state = %__MODULE__{state | configuration: config, initialized?: true}
    Logger.info("Starting project at uri #{config.project.root_uri}")

    event.id
    |> initialize_result()
    |> Transport.write()

    Transport.write(registrations())

    Project.Supervisor.start(config.project)
    {:ok, new_state}
  end

  def initialize(%__MODULE__{initialized?: true}, %Initialize{}) do
    {:error, :already_initialized}
  end

  def default_configuration(%__MODULE__{configuration: config}) do
    Configuration.default(config)
  end

  def apply(%__MODULE__{initialized?: false}, request) do
    Logger.error("Received #{request.method} before server was initialized")
    {:error, :not_initialized}
  end

  def apply(%__MODULE__{shutdown_received?: true} = state, %Exit{}) do
    Logger.warn("Received an Exit notification. Halting the server in 150ms")
    :timer.apply_after(50, System, :halt, [0])
    {:ok, state}
  end

  def apply(%__MODULE__{shutdown_received?: true}, request) do
    Logger.error("Received #{request.method} after shutdown. Ignoring")
    {:error, :shutting_down}
  end

  def apply(%__MODULE__{} = state, %DidChangeConfiguration{} = event) do
    case Configuration.on_change(state.configuration, event) do
      {:ok, config} ->
        {:ok, %__MODULE__{state | configuration: config}}

      {:ok, config, response} ->
        Transport.write(response)
        {:ok, %__MODULE__{state | configuration: config}}
    end

    {:ok, state}
  end

  def apply(%__MODULE__{} = state, %DidChange{lsp: event}) do
    uri = event.text_document.uri
    version = event.text_document.version

    case Document.Store.get_and_update(
           uri,
           &Document.apply_content_changes(&1, version, event.content_changes)
         ) do
      {:ok, updated_source} ->
        Api.compile_document(state.configuration.project, updated_source)
        throttle(&fetch_latest_and_enhance/2, :enhance_per_file, state.configuration.project, uri)
        {:ok, state}

      error ->
        error
    end
  end

  def apply(%__MODULE__{} = state, %DidOpen{lsp: event}) do
    %TextDocument.Item{text: text, uri: uri, version: version} =
      text_document = event.text_document

    case Document.Store.open(uri, text, version) do
      :ok ->
        Logger.info("opened #{uri}")
        {:ok, state}

      error ->
        Logger.error("Could not open #{text_document.uri} #{inspect(error)}")
        error
    end
  end

  def apply(%__MODULE__{} = state, %DidClose{lsp: event}) do
    uri = event.text_document.uri

    case Document.Store.close(uri) do
      :ok ->
        {:ok, state}

      error ->
        Logger.warn("Received textDocument/didClose for a file that wasn't open. URI was #{uri}")
        error
    end
  end

  def apply(%__MODULE__{} = state, %DidSave{lsp: event}) do
    uri = event.text_document.uri

    case Document.Store.save(uri) do
      :ok ->
        Api.schedule_compile(state.configuration.project, false)
        {:ok, state}

      error ->
        Logger.error("Save failed for uri #{uri} error was #{inspect(error)}")
        error
    end
  end

  def apply(%__MODULE__{} = state, %Initialized{}) do
    Logger.info("Lexical Initialized")
    {:ok, %__MODULE__{state | initialized?: true}}
  end

  def apply(%__MODULE__{} = state, %Shutdown{} = shutdown) do
    Transport.write(Responses.Shutdown.new(id: shutdown.id))
    Logger.error("Shutting down")

    {:ok, %__MODULE__{state | shutdown_received?: true}}
  end

  def apply(%__MODULE__{} = state, msg) do
    Logger.error("Ignoring unhandled message: #{inspect(msg)}")
    {:ok, state}
  end

  defp registrations do
    RegisterCapability.new(id: Id.next(), registrations: [file_watcher_registration()])
  end

  @did_changed_watched_files_id "-42"
  @watched_extensions ~w(ex exs)
  defp file_watcher_registration do
    extension_glob = "{" <> Enum.join(@watched_extensions, ",") <> "}"

    watchers = [
      FileSystemWatcher.new(glob_pattern: "**/mix.lock"),
      FileSystemWatcher.new(glob_pattern: "**/*.#{extension_glob}")
    ]

    Registration.new(
      id: @did_changed_watched_files_id,
      method: "workspace/didChangeWatchedFiles",
      register_options: DidChangeWatchedFiles.Registration.Options.new(watchers: watchers)
    )
  end

  def initialize_result(event_id) do
    sync_options =
      TextDocument.Sync.Options.new(open_close: true, change: :incremental, save: true)

    code_action_options =
      CodeAction.Options.new(code_action_kinds: @supported_code_actions, resolve_provider: false)

    completion_options =
      Completion.Options.new(trigger_characters: CodeIntelligence.Completion.trigger_characters())

    server_capabilities =
      Types.ServerCapabilities.new(
        code_action_provider: code_action_options,
        completion_provider: completion_options,
        definition_provider: true,
        document_formatting_provider: true,
        text_document_sync: sync_options
      )

    result =
      Types.Initialize.Result.new(
        capabilities: server_capabilities,
        server_info:
          Types.Initialize.Result.ServerInfo.new(
            name: "Lexical",
            version: "0.0.1"
          )
      )

    Responses.InitializeResult.new(event_id, result)
  end

  defp throttle(func, :enhance_per_file, project, uri) do
    fn ->
      func.(project, uri)
    end
    |> Throttler.JobInfo.new(:enhance_per_file, 250)
    |> Throttler.run()
  end

  defp fetch_latest_and_enhance(project, uri) do
    case Document.Store.fetch(uri) do
      {:ok, document} ->
        Api.enhance_by_plugin(project, document)
        :ok

      :error ->
        Logger.info("document already closed #{uri}")
        {:error, :document_not_found}
    end
  end
end
