# Glossary

This project uses a considerable amount of jargon, some adopted from the Language Server Protocol and some specific to Lexical.

This glossary attempts to define jargon used in this codebase.
Though it is not exhaustive, we hope it helps contributors more easily navigate and understand existing code and the goal, and that it provides some guidance for naming new things.

**You can help!** If you run across a new term while working on Lexical and you think it should be defined here, please [open an issue](https://github.com/lexical-lsp/lexical/issues) suggesting it!

## Language Server Protocol (LSP)

This section covers names and abstractions used by Lexical that have a direct correspondence to the Language Server Protocol.
For a definitive reference, see the [LSP Specification](https://microsoft.github.io/language-server-protocol/specifications/specification-current).

### Diagnostic
### Document

A single file identified by a URI and contains textual content.
Known as Text Document in LSP, documents in Lexical are always textual documents.

References: `Lexical.Document`

### Notification
### Position
### Request
### Response
### Text Edit
### URI
### Work Done Progress

## Lexical

This section covers names and abstractions introduced by Lexical.

### Code Intelligence
### Code Mod
### Convertible
### `Future.Code`
### Project
### Provider
### Translation
### Transport
