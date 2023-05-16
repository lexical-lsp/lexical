defmodule Lexical.Server.Configuration do
  alias Lexical.Project
  alias Lexical.Proto.LspTypes.Registration
  alias Lexical.Protocol.Id
  alias Lexical.Protocol.Notifications.DidChangeConfiguration
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Requests.RegisterCapability
  alias Lexical.Protocol.Types.ClientCapabilities
  alias Lexical.Server.Configuration.Support
  alias Lexical.Server.Dialyzer

  defstruct project: nil,
            support: nil,
            additional_watched_extensions: nil,
            dialyzer_enabled?: false

  @type t :: %__MODULE__{}
  @dialyzer {:nowarn_function, maybe_enable_dialyzer: 2}

  @spec new(Lexical.uri(), map()) :: t
  def new(root_uri, %ClientCapabilities{} = client_capabilities) do
    support = Support.new(client_capabilities)
    project = Project.new(root_uri)
    %__MODULE__{support: support, project: project} |> tap(&set/1)
  end

  @spec default(t | nil) ::
          {:ok, t}
          | {:ok, t, Requests.RegisterCapability.t()}
          | {:restart, Logger.level(), String.t()}
  def default(nil) do
    {:ok, default_config()}
  end

  def default(%__MODULE__{} = config) do
    apply_config_change(config, default_config())
  end

  @spec on_change(t, DidChangeConfiguration.t()) ::
          {:ok, t}
          | {:ok, t, Requests.RegisterCapability.t()}
          | {:restart, Logger.level(), String.t()}
  def on_change(%__MODULE__{} = old_config, :defaults) do
    apply_config_change(old_config, default_config())
  end

  def on_change(%__MODULE__{} = old_config, %DidChangeConfiguration{} = change) do
    apply_config_change(old_config, change.lsp.settings)
  end

  defp default_config do
    %{}
  end

  defp apply_config_change(%__MODULE__{} = old_config, %{} = settings) do
    with {:ok, new_config} <- maybe_enable_dialyzer(old_config, settings) do
      maybe_add_watched_extensions(new_config, settings)
    end
  end

  defp maybe_enable_dialyzer(%__MODULE__{} = old_config, settings) do
    enabled? =
      case Dialyzer.check_support() do
        :ok ->
          Map.get(settings, "dialyzerEnabled", true)

        _ ->
          false
      end

    {:ok, %__MODULE__{old_config | dialyzer_enabled?: enabled?}}
  end

  defp maybe_add_watched_extensions(%__MODULE__{} = old_config, %{
         "additionalWatchedExtensions" => []
       }) do
    {:ok, old_config}
  end

  defp maybe_add_watched_extensions(%__MODULE__{} = old_config, %{
         "additionalWatchedExtensions" => extensions
       })
       when is_list(extensions) do
    register_id = Id.next()
    request_id = Id.next()

    watchers = Enum.map(extensions, fn ext -> %{"globPattern" => "**/*#{ext}"} end)

    registration =
      Registration.new(
        id: request_id,
        method: "workspace/didChangeWatchedFiles",
        register_options: %{"watchers" => watchers}
      )

    request = RegisterCapability.new(id: register_id, registrations: [registration])

    {:ok, old_config, request}
  end

  defp maybe_add_watched_extensions(%__MODULE__{} = old_config, _) do
    {:ok, old_config}
  end

  @supports_keys ~w(work_done_progress?)a

  def supports?(key) when key in @supports_keys do
    get_in(get(), [Access.key(:support), Access.key(key)]) || false
  end

  def get do
    :persistent_term.get(__MODULE__, %__MODULE__{})
  end

  defp set(%__MODULE__{} = config) do
    :persistent_term.put(__MODULE__, config)
  end
end
