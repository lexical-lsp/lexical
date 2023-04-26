defmodule Lexical.Protocol.Integrations.InitializeTest do
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Types
  alias Lexical.Protocol.Types.Completion
  alias Lexical.Protocol.Types.TextDocument

  use ExUnit.Case

  test "initialize parses a request from neovim" do
    assert {:ok, %Requests.Initialize{lsp: %Requests.Initialize.LSP{} = parsed}} =
             Requests.Initialize.parse(neovim_initialize())

    assert parsed.client_info.name == "Neovim"
    assert parsed.client_info.version == "0.10.0"

    assert %Types.ClientCapabilities{} = capabilities = parsed.capabilities

    assert %TextDocument.ClientCapabilities{} = text_doc_capabilities = capabilities.text_document

    validate_workspace(capabilities)

    validate_call_hierarchy(text_doc_capabilities)
    validate_code_action(text_doc_capabilities)
    validate_declaration(text_doc_capabilities)
    validate_definition(text_doc_capabilities)
    validate_completion(text_doc_capabilities)
  end

  def validate_completion(%TextDocument.ClientCapabilities{} = text_doc_capabilities) do
    assert %Completion.ClientCapabilities{} =
             completion_capabilities = text_doc_capabilities.completion

    assert %Completion.ClientCapabilities.CompletionItemKind{} =
             completion_capabilities.completion_item_kind
  end

  def validate_call_hierarchy(%TextDocument.ClientCapabilities{} = text_doc_capabilities) do
    assert %Types.CallHierarchy.ClientCapabilities{} = text_doc_capabilities.call_hierarchy
  end

  def validate_code_action(%TextDocument.ClientCapabilities{} = text_doc_capabilities) do
    assert %Types.CodeAction.ClientCapabilities{} = text_doc_capabilities.code_action
  end

  def validate_declaration(%TextDocument.ClientCapabilities{} = text_doc_capabilities) do
    assert %Types.Declaration.ClientCapabilities{} = text_doc_capabilities.declaration
  end

  def validate_definition(%TextDocument.ClientCapabilities{} = text_doc_capabilities) do
    assert %Types.Definition.ClientCapabilities{} = text_doc_capabilities.definition
  end

  def validate_workspace(%Types.ClientCapabilities{} = capabilities) do
    assert %Types.Workspace.ClientCapabilities{} = capabilities.workspace
  end

  def neovim_initialize do
    ~S(
      {
        "id": 1,
        "jsonrpc": "2.0",
        "method": "initialize",
        "params": {
          "capabilities": {
            "textDocument": {
              "callHierarchy": {
                "dynamicRegistration": false
              },
              "codeAction": {
                "codeActionLiteralSupport": {
                  "codeActionKind": {
                    "valueSet": ["", "quickfix", "refactor", "refactor.extract", "refactor.inline", "refactor.rewrite", "source", "source.organizeImports"]
                  }
                },
                "dataSupport": true,
                "dynamicRegistration": false,
                "isPreferredSupport": true,
                "resolveSupport": {
                  "properties": [ "edit" ]
                }
              },
              "completion": {
                "completionItem": {
                  "commitCharactersSupport": false,
                  "deprecatedSupport": false,
                  "documentationFormat": [ "markdown", "plaintext" ],
                  "preselectSupport": false,
                  "snippetSupport": false
                },
                "completionItemKind": {
                  "valueSet": [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25 ]
                },
                "contextSupport": false,
                "dynamicRegistration": false
              },
              "declaration": {
                "linkSupport": true
              },
              "definition": {
                "linkSupport": true
              },
              "documentHighlight": {
                "dynamicRegistration": false
              },
              "documentSymbol": {
                "dynamicRegistration": false,
                "hierarchicalDocumentSymbolSupport": true,
                "symbolKind": {
                  "valueSet": [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26 ]
                }
              },
              "hover": {
                "contentFormat": [ "markdown", "plaintext" ],
                "dynamicRegistration": false
              },
              "implementation": {
                "linkSupport": true
              },
              "publishDiagnostics": {
                "relatedInformation": true,
                "tagSupport": {
                  "valueSet": [ 1, 2 ]
                }
              },
              "references": {
                "dynamicRegistration": false
              },
              "rename": {
                "dynamicRegistration": false,
                "prepareSupport": true
              },
              "semanticTokens": {
                "augmentsSyntaxTokens": true,
                "dynamicRegistration": false,
                "formats": [ "relative" ],
                "multilineTokenSupport": false,
                "overlappingTokenSupport": true,
                "requests": {
                  "full": {
                    "delta": true
                  },
                  "range": false
                },
                "serverCancelSupport": false,
                "tokenModifiers": [ "declaration", "definition", "readonly", "static", "deprecated", "abstract", "async", "modification", "documentation", "defaultLibrary" ],
                "tokenTypes": [ "namespace", "type", "class", "enum", "interface", "struct", "typeParameter", "parameter", "variable", "property", "enumMember", "event", "function", "method", "macro", "keyword", "modifier", "comment", "string", "number", "regexp", "operator", "decorator" ]
              },
              "signatureHelp": {
                "dynamicRegistration": false,
                "signatureInformation": {
                  "activeParameterSupport": true,
                  "documentationFormat": [ "markdown", "plaintext" ],
                  "parameterInformation": {
                    "labelOffsetSupport": true
                  }
                }
              },
              "synchronization": {
                "didSave": true,
                "dynamicRegistration": false,
                "willSave": true,
                "willSaveWaitUntil": true
              },
              "typeDefinition": {
                "linkSupport": true
              }
            },
            "window": {
              "showDocument": {
                "support": true
              },
              "showMessage": {
                "messageActionItem": {
                  "additionalPropertiesSupport": false
                }
              },
              "workDoneProgress": true
            },
            "workspace": {
              "applyEdit": true,
              "configuration": true,
              "didChangeWatchedFiles": {
                "dynamicRegistration": false,
                "relativePatternSupport": true
              },
              "semanticTokens": {
                "refreshSupport": true
              },
              "symbol": {
                "dynamicRegistration": false,
                "hierarchicalWorkspaceSymbolSupport": true,
                "symbolKind": {
                  "valueSet": [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26 ]
                }
              },
              "workspaceEdit": {
                "resourceOperations": ["rename", "create", "delete"]
              },
              "workspaceFolders": true
            }
          },
          "clientInfo": {
            "name": "Neovim",
            "version": "0.10.0"
          },
          "processId": 81648,
          "rootPath": "/Users/scottming/Code/lexical",
          "rootUri": "file:///Users/scottming/Code/lexical",
          "trace": "off",
          "workspaceFolders": [
            {
              "name": "/Users/scottming/Code/lexical",
              "uri": "file:///Users/scottming/Code/lexical"
            }
          ]
        }
      }
    )
    |> Jason.decode!()
  end
end
