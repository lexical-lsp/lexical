# Glossary
This project uses a considerable amount of jargon, some adopted from the Language Server Protocol and some specific to Lexical.

This glossary attempts to define jargon used in this codebase.
Though it is not exhaustive, we hope it helps contributors more easily navigate and understand existing code and the goal, and that it provides some guidance for naming new things.

**You can help!** If you run across a new term while working on Lexical and you think it should be defined here, please [open an issue](https://github.com/lexical-lsp/lexical/issues) suggesting it!

## Language Server Protocol (LSP)
This section covers features, names, and abstractions used by Lexical that have a correspondence to the Language Server Protocol. For a definitive reference, see the [LSP Specification](https://microsoft.github.io/language-server-protocol/specifications/specification-current).

### Messages, Requests, Responses, and Notifications
LSP defines a general heirarchy of the types of messages langauge servers and clients and may exchange, and the expected behaviours associated with them.

There's 3 top-level types of Messages: [Requests](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#requestMessage), [Responses](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#responseMessage), and [Notifications](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#notificationMessage):

- [Requests](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#requestMessage) can be sent from client to server and vice versa, and must always be answered with a [Response](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#responseMessage).

- [Notifications](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#notificationMessage) are likewise bi-directional and work like events. They expressly do not receive responses per LSP's specification.

From these 3 top-level types, LSP defines more specific more concrete, actionable messages such as:
- [Completion Requests](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_completion)
- [Goto Definition Requests](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_definition)
- [WillSaveTextDocument Notifications](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_willSave)

... and many more. These can serve as good reference for the specific features you're working on.

Finally worth noting, all messages are JSON, specifically [JSON-RPC version 2.0](https://www.jsonrpc.org/specification).

**Todo: explain exactly what Lexical autogenerates from LSP's specification.**

### Document(s)
A single file identified by a URI and contains textual content. Formally referred to as [Text Documents](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocuments) in LSP and modeled as [`Document`](/projects/lexical_shared/lib/lexical/document.ex) structs in Lexical.

### Completions and Code Intelligence
Auto-completion suggestions that appear in an editor's IntelliSense. For example, a user that's typed `IO.in|` may be suggested `IO.inspect(|)` as one of a few possible completions.

**Todo:**
- Explain the completion request cycle.
- Define "completion contexts", "ast environments", and how they inform completions. 
- Note Lexical's current support for things like [merging multiple contextual conditions](https://github.com/lexical-lsp/lexical/issues/284).
- Explain where Lexical does/doesn't delegate to [elixir-sense](https://github.com/elixir-lsp/elixir_sense).
- Note that LSP clients sort and filter completion items independent of language servers.
  - The language server provides meaningful values for the client to do so.

### Diagnostics
Represents a diagnostic, such as a compiler error or warning. Diagnostic objects are only valid in the scope of a resource.

## Concepts exclusive to Lexical
This section covers names and abstractions introduced by Lexical.

### Project
- It's just a struct underneath! But an important one.

### Providers
- What do they represent? Are there good analogs people are familiar with?

### Code Mod
### Convertible
### `Future.Code`
### Provider
### Translation
### Transport
