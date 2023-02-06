defmodule Lexical.RemoteControl.Api.Messages do
  import Record
  defrecord :project_compiled, project: nil, status: :successful, diagnostics: [], elapsed_ms: 0

  defrecord :file_compile_requested, uri: nil

  defrecord :file_compiled,
    project: nil,
    source_file: nil,
    status: :successful,
    diagnostics: [],
    elapsed_ms: 0

  defrecord :module_updated, name: nil, functions: [], macros: []
end
