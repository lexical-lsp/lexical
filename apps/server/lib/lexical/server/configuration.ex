defmodule Lexical.Server.Configuration do
  @moduledoc """
  Encapsulates server configuration options and client capability support.
  """

  alias Lexical.Project
  alias Lexical.Protocol.Id
  alias Lexical.Protocol.Notifications.DidChangeConfiguration
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Requests.RegisterCapability
  alias Lexical.Protocol.Types.ClientCapabilities
  alias Lexical.Protocol.Types.Registration
  alias Lexical.Server.Configuration.Support
  alias Lexical.Server.Dialyzer

  defstruct project: nil,
            support: nil,
            client_name: nil,
            additional_watched_extensions: nil,
            dialyzer_enabled?: false

  @type t :: %__MODULE__{
          project: Project.t() | nil,
          support: support | nil,
          client_name: String.t() | nil,
          additional_watched_extensions: [String.t()] | nil,
          dialyzer_enabled?: boolean()
        }

  @opaque support :: Support.t()

  @dialyzer {:nowarn_function, set_dialyzer_enabled: 2}

  @spec new(Lexical.uri(), map(), String.t() | nil) :: t
  def new(root_uri, %ClientCapabilities{} = client_capabilities, client_name) do
    support = Support.new(client_capabilities)
    project = Project.new(root_uri)

    %__MODULE__{support: support, project: project, client_name: client_name}
    |> tap(&set/1)
  end

  @spec new(keyword()) :: t
  def new(attrs \\ []) do
    struct!(__MODULE__, [support: Support.new()] ++ attrs)
  end

  defp set(%__MODULE__{} = config) do
    :persistent_term.put(__MODULE__, config)
  end

  @spec get() :: t
  def get do
    :persistent_term.get(__MODULE__, false) || new()
  end

  @spec client_supports?(atom()) :: boolean()
  def client_supports?(key) when is_atom(key) do
    client_supports?(get().support, key)
  end

  defp client_supports?(%Support{} = client_support, key) do
    case Map.fetch(client_support, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "unknown key: #{inspect(key)}"
    end
  end

  @spec default(t | nil) ::
          {:ok, t}
          | {:ok, t, Requests.RegisterCapability.t()}
  def default(nil) do
    {:ok, default_config()}
  end

  def default(%__MODULE__{} = config) do
    apply_config_change(config, default_config())
  end

  @spec on_change(t, DidChangeConfiguration.t()) ::
          {:ok, t}
          | {:ok, t, Requests.RegisterCapability.t()}
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
    old_config
    |> set_dialyzer_enabled(settings)
    |> maybe_add_watched_extensions(settings)
  end

  defp set_dialyzer_enabled(%__MODULE__{} = old_config, settings) do
    enabled? =
      if Dialyzer.check_support() == :ok do
        Map.get(settings, "dialyzerEnabled", true)
      else
        false
      end

    %__MODULE__{old_config | dialyzer_enabled?: enabled?}
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
end
