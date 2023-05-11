defmodule Lexical.RemoteControl.Api.Messages do
  import Record
  defrecord :project_compiled, project: nil, status: :successful, diagnostics: [], elapsed_ms: 0

  defrecord :file_compile_requested, uri: nil

  defrecord :file_compiled,
    project: nil,
    uri: nil,
    status: :successful,
    diagnostics: [],
    elapsed_ms: 0

  defrecord :module_updated, name: nil, functions: [], macros: [], struct: nil

  defrecord :project_diagnostics, project: nil, diagnostics: []
  defrecord :file_diagnostics, project: nil, uri: nil, diagnostics: []

  defrecord :project_progress, label: nil, message: nil, stage: nil

  @type compile_status :: :successful | :error
  @type name_and_arity :: {atom, non_neg_integer}
  @type field_list :: Keyword.t() | [atom]
  @type diagnostics :: [Mix.Task.Compiler.Diagnostic.t()]

  @type project_compiled ::
          record(:project_compiled,
            project: Lexical.Project.t(),
            status: compile_status,
            elapsed_ms: non_neg_integer
          )

  @type file_compile_requested :: record(:file_compile_requested, uri: Lexical.uri())

  @type file_compiled ::
          record(:file_compiled,
            uri: Lexical.uri(),
            project: Lexical.Project.t(),
            status: compile_status,
            elapsed_ms: non_neg_integer
          )

  @type module_updated ::
          record(:module_updated,
            name: module(),
            functions: [name_and_arity],
            macros: [name_and_arity],
            struct: field_list
          )

  @type project_diagnostics ::
          record(:project_diagnostics,
            project: Lexical.Project.t(),
            diagnostics: diagnostics()
          )

  @type file_diagnostics ::
          record(:file_diagnostics,
            project: Lexical.Project.t(),
            uri: Lexical.uri(),
            diagnostics: diagnostics()
          )

  @type project_progress ::
          record(:project_progress,
            label: String.t(),
            message: String.t() | integer(),
            stage: :prepare | :begin | :report | :end
          )
end
