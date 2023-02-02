defmodule Lexical.Server.State do
  alias Lexical.Transport

  alias Lexical.Protocol.Notifications.{
    DidChange,
    DidChangeConfiguration,
    DidClose,
    DidOpen,
    DidSave
  }

  alias Lexical.Protocol.Responses
  alias Lexical.Protocol.Types
  alias Lexical.Protocol.Types.CodeAction
  alias Lexical.Protocol.Requests.Initialize
  alias Lexical.Protocol.Types.TextDocument
  alias Lexical.Server.Configuration
  alias Lexical.SourceFile

  import Logger

  require CodeAction.Kind

  defstruct configuration: nil, initialized?: false

  @supported_code_actions [
    CodeAction.Kind.quick_fix()
  ]

  def new do
    %__MODULE__{}
  end

  def initialize(%__MODULE__{initialized?: false} = state, %Initialize{
        lsp: %Initialize.LSP{} = event
      }) do
    config = Configuration.new(event.root_uri, event.capabilities)
    new_state = %__MODULE__{state | configuration: config, initialized?: true}
    info("Starting project at uri #{config.project.root_uri}")

    Lexical.Server.Project.Supervisor.start(config.project)

    event.id
    |> initialize_result()
    |> Transport.write()

    {:ok, new_state}
  end

  def initialize(%__MODULE__{initialized?: true}, %Initialize{}) do
    {:error, :already_initialized}
  end

  def default_configuration(%__MODULE__{configuration: config} = state) do
    with {:ok, config} <- Configuration.default(config) do
      {:ok, %__MODULE__{state | configuration: config}}
    end
  end

  def apply(%__MODULE__{initialized?: false}, request) do
    Logger.error("Received #{request.method} before server was initialized")
    {:error, :not_initialized}
  end

  def apply(%__MODULE__{} = state, %DidChangeConfiguration{} = event) do
    case Configuration.on_change(state.configuration, event) do
      {:ok, config} ->
        {:ok, %__MODULE__{state | configuration: config}}

      {:ok, config, response} ->
        Transport.write(response)
        {:ok, %__MODULE__{state | configuration: config}}

      error ->
        error
    end

    {:ok, state}
  end

  def apply(%__MODULE__{} = state, %DidChange{lsp: event}) do
    uri = event.text_document.uri
    version = event.text_document.version

    case SourceFile.Store.update(
           uri,
           &SourceFile.apply_content_changes(&1, version, event.content_changes)
         ) do
      :ok -> {:ok, state}
      error -> error
    end
  end

  def apply(%__MODULE__{} = state, %DidOpen{lsp: event}) do
    %TextDocument.Item{text: text, uri: uri, version: version} =
      text_document = event.text_document

    case SourceFile.Store.open(uri, text, version) do
      :ok ->
        info("opened #{uri}")
        {:ok, state}

      error ->
        error("Could not open #{text_document.uri} #{inspect(error)}")
        error
    end
  end

  def apply(%__MODULE__{} = state, %DidClose{lsp: event}) do
    uri = event.text_document.uri

    case SourceFile.Store.close(uri) do
      :ok ->
        {:ok, state}

      error ->
        warn("Received textDocument/didClose for a file that wasn't open. URI was #{uri}")
        error
    end
  end

  def apply(%__MODULE__{} = state, %DidSave{lsp: event}) do
    uri = event.text_document.uri

    case SourceFile.Store.save(uri) do
      :ok ->
        {:ok, state}

      error ->
        warn("Save failed for uri #{uri} error was #{inspect(error)}")
        error
    end
  end

  def apply(%__MODULE__{} = state, msg) do
    Transport.log("Applying unknown #{inspect(msg)}")
    {:ok, state}
  end

  def initialize_result(event_id) do
    sync_options = TextDocument.Sync.Options.new(open_close: true, change: :incremental)

    code_action_options =
      CodeAction.Options.new(code_action_kinds: @supported_code_actions, resolve_provider: false)

    server_capabilities =
      Types.ServerCapabilities.new(
        code_action_provider: true,
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
end
