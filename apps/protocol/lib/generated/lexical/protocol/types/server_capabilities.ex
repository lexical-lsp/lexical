# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.ServerCapabilities do
  alias Lexical.Protocol.Proto
  alias Lexical.Protocol.Types
  alias __MODULE__, as: Parent

  defmodule Workspace do
    use Proto

    deftype file_operations: optional(Types.FileOperation.Options),
            workspace_folders: optional(Types.Workspace.FoldersServerCapabilities)
  end

  use Proto

  deftype call_hierarchy_provider:
            optional(
              one_of([
                boolean(),
                Types.CallHierarchy.Options,
                Types.CallHierarchy.Registration.Options
              ])
            ),
          code_action_provider: optional(one_of([boolean(), Types.CodeAction.Options])),
          code_lens_provider: optional(Types.CodeLens.Options),
          color_provider:
            optional(
              one_of([
                boolean(),
                Types.Document.Color.Options,
                Types.Document.Color.Registration.Options
              ])
            ),
          completion_provider: optional(Types.Completion.Options),
          declaration_provider:
            optional(
              one_of([
                boolean(),
                Types.Declaration.Options,
                Types.Declaration.Registration.Options
              ])
            ),
          definition_provider: optional(one_of([boolean(), Types.Definition.Options])),
          diagnostic_provider:
            optional(one_of([Types.Diagnostic.Options, Types.Diagnostic.Registration.Options])),
          document_formatting_provider:
            optional(one_of([boolean(), Types.Document.Formatting.Options])),
          document_highlight_provider:
            optional(one_of([boolean(), Types.Document.Highlight.Options])),
          document_link_provider: optional(Types.Document.Link.Options),
          document_on_type_formatting_provider: optional(Types.Document.OnTypeFormatting.Options),
          document_range_formatting_provider:
            optional(one_of([boolean(), Types.Document.RangeFormatting.Options])),
          document_symbol_provider: optional(one_of([boolean(), Types.Document.Symbol.Options])),
          execute_command_provider: optional(Types.ExecuteCommand.Options),
          experimental: optional(any()),
          folding_range_provider:
            optional(
              one_of([
                boolean(),
                Types.FoldingRange.Options,
                Types.FoldingRange.Registration.Options
              ])
            ),
          hover_provider: optional(one_of([boolean(), Types.Hover.Options])),
          implementation_provider:
            optional(
              one_of([
                boolean(),
                Types.Implementation.Options,
                Types.Implementation.Registration.Options
              ])
            ),
          inlay_hint_provider:
            optional(
              one_of([boolean(), Types.InlayHint.Options, Types.InlayHint.Registration.Options])
            ),
          inline_value_provider:
            optional(
              one_of([
                boolean(),
                Types.InlineValue.Options,
                Types.InlineValue.Registration.Options
              ])
            ),
          linked_editing_range_provider:
            optional(
              one_of([
                boolean(),
                Types.LinkedEditingRange.Options,
                Types.LinkedEditingRange.Registration.Options
              ])
            ),
          moniker_provider:
            optional(
              one_of([boolean(), Types.Moniker.Options, Types.Moniker.Registration.Options])
            ),
          notebook_document_sync:
            optional(
              one_of([
                Types.Notebook.Document.Sync.Options,
                Types.Notebook.Document.Sync.Registration.Options
              ])
            ),
          position_encoding: optional(Types.Position.Encoding.Kind),
          references_provider: optional(one_of([boolean(), Types.Reference.Options])),
          rename_provider: optional(one_of([boolean(), Types.Rename.Options])),
          selection_range_provider:
            optional(
              one_of([
                boolean(),
                Types.SelectionRange.Options,
                Types.SelectionRange.Registration.Options
              ])
            ),
          semantic_tokens_provider:
            optional(
              one_of([Types.SemanticTokens.Options, Types.SemanticTokens.Registration.Options])
            ),
          signature_help_provider: optional(Types.SignatureHelp.Options),
          text_document_sync:
            optional(one_of([Types.TextDocument.Sync.Options, Types.TextDocument.Sync.Kind])),
          type_definition_provider:
            optional(
              one_of([
                boolean(),
                Types.TypeDefinition.Options,
                Types.TypeDefinition.Registration.Options
              ])
            ),
          type_hierarchy_provider:
            optional(
              one_of([
                boolean(),
                Types.TypeHierarchy.Options,
                Types.TypeHierarchy.Registration.Options
              ])
            ),
          workspace: optional(Parent.Workspace),
          workspace_symbol_provider: optional(one_of([boolean(), Types.Workspace.Symbol.Options]))
end
