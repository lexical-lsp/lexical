defmodule Lexical.RemoteControl.Api.Messages do
  alias Lexical.Project

  import Record
  defrecord :project_compile_requested, project: nil, build_number: 0

  defrecord :project_compiled,
    project: nil,
    build_number: 0,
    status: :successful,
    diagnostics: [],
    elapsed_ms: 0

  defrecord :filesystem_event, project: nil, uri: nil, event_type: nil

  defrecord :file_changed, uri: nil, from_version: nil, to_version: nil, open?: false

  defrecord :file_compile_requested, project: nil, build_number: 0, uri: nil

  defrecord :file_quoted, project: nil, document: nil, quoted_ast: nil

  defrecord :file_compiled,
    project: nil,
    build_number: 0,
    uri: nil,
    status: :successful,
    diagnostics: [],
    elapsed_ms: 0

  defrecord :file_deleted, project: nil, uri: nil

  defrecord :module_updated, file: nil, name: nil, functions: [], macros: [], struct: nil

  defrecord :project_diagnostics, project: nil, build_number: 0, diagnostics: []
  defrecord :file_diagnostics, project: nil, build_number: 0, uri: nil, diagnostics: []

  defrecord :project_progress, label: nil, message: nil, stage: :report

  defrecord :struct_discovered, module: nil, fields: []

  @type compile_status :: :successful | :error
  @type name_and_arity :: {atom, non_neg_integer}
  @type field_list :: Keyword.t() | [atom]
  @type diagnostics :: [Mix.Task.Compiler.Diagnostic.t()]
  @type maybe_version :: nil | non_neg_integer()

  @type project_compile_requested ::
          record(:project_compile_requested,
            project: Lexical.Project.t(),
            build_number: non_neg_integer()
          )
  @type project_compiled ::
          record(:project_compiled,
            project: Lexical.Project.t(),
            build_number: non_neg_integer(),
            status: compile_status,
            elapsed_ms: non_neg_integer
          )

  @type filesystem_event ::
          record(:filesystem_event,
            project: Project.t(),
            uri: Lexical.uri(),
            event_type: :created | :updated | :deleted
          )

  @type file_changed ::
          record(:file_changed,
            uri: Lexical.uri(),
            from_version: maybe_version,
            to_version: maybe_version,
            open?: boolean()
          )
  @type file_compile_requested ::
          record(:file_compile_requested,
            project: Lexical.Project.t(),
            build_number: non_neg_integer(),
            uri: Lexical.uri()
          )

  @type file_quoted ::
          record(:file_quoted,
            project: Lexical.Project.t(),
            document: Lexical.Document.t(),
            quoted_ast: Macro.t()
          )

  @type file_compiled ::
          record(:file_compiled,
            project: Lexical.Project.t(),
            build_number: non_neg_integer(),
            uri: Lexical.uri(),
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
            stage: :prepare | :begin | :report | :complete
          )

  @type struct_discovered :: record(:struct_discovered, module: module(), fields: field_list())
end
