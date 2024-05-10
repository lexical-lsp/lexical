defmodule Lexical.RemoteControl.Api.Local do
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Proxy
  alias Lexical.RemoteControl.CodeAction
  alias Lexical.RemoteControl.CodeIntelligence

  defdelegate schedule_compile(force?), to: Proxy

  defdelegate compile_document(document), to: Proxy

  defdelegate format(document), to: Proxy

  defdelegate reindex, to: Proxy

  defdelegate index_running?, to: Proxy

  defdelegate expand_alias(segments_or_module, analysis, position), to: RemoteControl.Analyzer

  defdelegate list_modules, to: :code, as: :all_available

  defdelegate code_actions(document, range, diagnostics, kinds), to: CodeAction, as: :for_range

  defdelegate complete(env), to: RemoteControl.Completion, as: :elixir_sense_expand

  defdelegate complete_struct_fields(analysis, position),
    to: RemoteControl.Completion,
    as: :struct_fields

  defdelegate definition(document, position), to: CodeIntelligence.Definition

  defdelegate references(analysis, position, include_definitions?),
    to: CodeIntelligence.References

  defdelegate modules_with_prefix(prefix), to: RemoteControl.Modules, as: :with_prefix

  defdelegate modules_with_prefix(prefix, predicate), to: RemoteControl.Modules, as: :with_prefix

  @spec docs(Project.t(), module()) :: {:ok, CodeIntelligence.Docs.t()} | {:error, any()}
  defdelegate docs(module, opts \\ []), to: CodeIntelligence.Docs, as: :for_module

  defdelegate register_listener(listener_pid, message_types), to: RemoteControl.Dispatch

  defdelegate broadcast(message), to: RemoteControl.Dispatch

  defdelegate resolve_entity(analysis, position), to: CodeIntelligence.Entity, as: :resolve

  defdelegate struct_definitions, to: CodeIntelligence.Structs, as: :for_project

  defdelegate document_symbols(document), to: CodeIntelligence.Symbols, as: :for_document

  defdelegate workspace_symbols(query), to: CodeIntelligence.Symbols, as: :for_workspace
end
