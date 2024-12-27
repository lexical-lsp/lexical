# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.Initialize.Params do
  alias Lexical.Proto
  alias Lexical.Protocol.Types

  defmodule ClientInfo1 do
    use Proto
    deftype name: string(), version: optional(string())
  end

  use Proto

  deftype capabilities: Types.ClientCapabilities,
          client_info: optional(Lexical.Protocol.Types.Initialize.Params.ClientInfo1),
          initialization_options: optional(any()),
          locale: optional(string()),
          process_id: one_of([integer(), nil]),
          root_path: optional(one_of([string(), nil])),
          root_uri: one_of([string(), nil]),
          trace:
            optional(
              one_of([
                literal("off"),
                literal("messages"),
                literal("compact"),
                literal("verbose")
              ])
            ),
          work_done_token: optional(Types.Progress.Token),
          workspace_folders: optional(one_of([list_of(Types.Workspace.Folder), nil]))
end
