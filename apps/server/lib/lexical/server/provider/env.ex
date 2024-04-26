defmodule Lexical.Server.Provider.Env do
  @moduledoc """
  An environment passed to provider handlers.
  This represents the current state of the project, and should include additional
  information that provider handles might need to complete their tasks.
  """

  alias Lexical.Project
  alias Lexical.Server.Configuration

  defstruct [:project, :client_name]

  @type t :: %__MODULE__{
          project: Project.t(),
          client_name: String.t() | nil
        }

  def new do
    %__MODULE__{}
  end

  def from_configuration(%Configuration{} = config) do
    %__MODULE__{project: config.project, client_name: config.client_name}
  end

  def project_name(%__MODULE__{} = env) do
    Project.name(env.project)
  end
end
